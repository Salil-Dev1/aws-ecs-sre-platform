"""TaskFlow API prototype; the next commit adds production readiness."""

import json
import logging
import os
import time
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import Response
from prometheus_client import CONTENT_TYPE_LATEST, CollectorRegistry, Counter, Gauge, Histogram, generate_latest
from pydantic import BaseModel, Field
from pymongo import MongoClient

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("taskflow")
registry = CollectorRegistry()
REQUESTS = Counter("http_requests_total", "HTTP requests", ["method", "path", "status"], registry=registry)
LATENCY = Histogram("http_request_duration_seconds", "HTTP request latency", ["method", "path"], registry=registry)
DB_HEALTH = Gauge("database_health", "MongoDB connection health", registry=registry)


class ItemInput(BaseModel):
    title: str = Field(min_length=1, max_length=200)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Prototype flaw: silently defaults to localhost with no PyMongo timeouts.
    app.state.client = MongoClient(os.getenv("MONGO_URI", "mongodb://localhost:27017"))
    app.state.items = app.state.client.taskflow.items
    yield
    app.state.client.close()


def create_app() -> FastAPI:
    application = FastAPI(title="TaskFlow API", lifespan=lifespan)

    @application.middleware("http")
    async def observe_request(request: Request, call_next):
        request_id = request.headers.get("X-Request-ID") or str(uuid.uuid4())
        started = time.perf_counter()
        status = 500
        try:
            response = await call_next(request)
            status = response.status_code
            response.headers["X-Request-ID"] = request_id
            return response
        finally:
            duration = time.perf_counter() - started
            route = getattr(request.scope.get("route"), "path", request.url.path)
            REQUESTS.labels(request.method, route, str(status)).inc()
            LATENCY.labels(request.method, route).observe(duration)
            logger.info(json.dumps({"timestamp": datetime.now(timezone.utc).isoformat(), "level": "INFO", "request_id": request_id, "method": request.method, "path": request.url.path, "status": status, "duration_ms": round(duration * 1000, 1)}))

    @application.get("/health")
    def health(request: Request):
        request.app.state.client.admin.command("ping")
        DB_HEALTH.set(1)
        return {"status": "ok", "db": "connected"}

    @application.get("/metrics")
    def metrics():
        return Response(generate_latest(registry), media_type=CONTENT_TYPE_LATEST)

    @application.get("/api/items")
    def list_items(request: Request):
        return [{"id": str(item.pop("_id")), **item} for item in request.app.state.items.find()]

    @application.post("/api/items", status_code=201)
    def create_item(payload: ItemInput, request: Request):
        result = request.app.state.items.insert_one({"title": payload.title})
        return {"id": str(result.inserted_id), "title": payload.title}

    @application.delete("/api/items/{item_id}")
    def delete_item(item_id: str, request: Request):
        from bson import ObjectId
        result = request.app.state.items.delete_one({"_id": ObjectId(item_id)})
        if result.deleted_count == 0:
            raise HTTPException(status_code=404, detail="Item not found")
        return {"deleted": True}

    return application


app = create_app()
