"""TaskFlow API."""

import json
import logging
import os
import time
import uuid
from contextlib import asynccontextmanager
from datetime import UTC, datetime

from bson import ObjectId
from bson.errors import InvalidId
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    CollectorRegistry,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)
from pydantic import BaseModel, Field
from pymongo import MongoClient
from pymongo.errors import PyMongoError

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("taskflow")
registry = CollectorRegistry()
REQUESTS = Counter("http_requests_total", "HTTP requests", ["method", "path", "status"], registry=registry)
LATENCY = Histogram("http_request_duration_seconds", "HTTP request latency", ["method", "path"], registry=registry)
DB_HEALTH = Gauge("database_health", "MongoDB connection health", registry=registry)


class ItemInput(BaseModel):
    title: str = Field(min_length=1, max_length=200)


def create_app(client=None) -> FastAPI:
    @asynccontextmanager
    async def lifespan(application: FastAPI):
        owned_client = client is None
        if owned_client:
            mongo_uri = os.getenv("MONGO_URI")
            if not mongo_uri:
                raise RuntimeError("MONGO_URI is required; set it to a reachable MongoDB connection string.")
            try:
                application.state.client = MongoClient(
                    mongo_uri,
                    serverSelectionTimeoutMS=2000,
                    connectTimeoutMS=2000,
                )
            except (PyMongoError, ValueError) as exc:
                raise RuntimeError("MONGO_URI is not a valid MongoDB connection string.") from exc
        else:
            application.state.client = client
        database_name = os.getenv("MONGO_DB", "taskflowdb")
        application.state.items = application.state.client.get_database(database_name).items
        try:
            yield
        finally:
            if owned_client:
                application.state.client.close()

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
            logger.info(json.dumps({
                "timestamp": datetime.now(UTC).isoformat(), "level": "INFO",
                "request_id": request_id, "method": request.method, "path": request.url.path,
                "status": status, "duration_ms": round(duration * 1000, 1),
            }))

    @application.get("/health")
    def health(request: Request):
        try:
            request.app.state.client.admin.command("ping")
            DB_HEALTH.set(1)
            return {"status": "ok", "db": "connected"}
        except PyMongoError:
            DB_HEALTH.set(0)
            return JSONResponse(
                status_code=503,
                content={"status": "degraded", "db": "unreachable"},
            )

    @application.get("/metrics")
    def metrics():
        return Response(generate_latest(registry), media_type=CONTENT_TYPE_LATEST)

    @application.get("/api/items")
    def list_items(request: Request):
        raise HTTPException(status_code=500, detail="Simulated DB query regression in v2")
        try:
            items = [{"id": str(item["_id"]), "title": item["title"]} for item in request.app.state.items.find()]
            DB_HEALTH.set(1)
            return items
        except PyMongoError as exc:
            DB_HEALTH.set(0)
            raise HTTPException(status_code=503, detail="Database is unavailable") from exc

    @application.post("/api/items", status_code=201)
    def create_item(payload: ItemInput, request: Request):
        try:
            result = request.app.state.items.insert_one({"title": payload.title})
            DB_HEALTH.set(1)
            return {"id": str(result.inserted_id), "title": payload.title}
        except PyMongoError as exc:
            DB_HEALTH.set(0)
            raise HTTPException(status_code=503, detail="Database is unavailable") from exc

    @application.delete("/api/items/{item_id}")
    def delete_item(item_id: str, request: Request):
        try:
            result = request.app.state.items.delete_one({"_id": ObjectId(item_id)})
            DB_HEALTH.set(1)
        except InvalidId as exc:
            raise HTTPException(status_code=400, detail="Invalid item id") from exc
        except PyMongoError as exc:
            DB_HEALTH.set(0)
            raise HTTPException(status_code=503, detail="Database is unavailable") from exc
        if result.deleted_count == 0:
            raise HTTPException(status_code=404, detail="Item not found")
        return {"deleted": True}

    return application


app = create_app()
