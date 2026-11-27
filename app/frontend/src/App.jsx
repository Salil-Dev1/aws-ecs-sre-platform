import { useCallback, useEffect, useState } from 'react';

export default function App() {
  const [items, setItems] = useState([]);
  const [title, setTitle] = useState('');
  const [health, setHealth] = useState('checking');
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    try {
      const [itemResponse, healthResponse] = await Promise.all([fetch('/api/items'), fetch('/health')]);
      if (!itemResponse.ok) throw new Error(`Items request failed (${itemResponse.status})`);
      setItems(await itemResponse.json());
      setHealth(healthResponse.ok ? 'connected' : 'degraded');
      setError('');
    } catch (err) {
      setHealth('unreachable');
      setError(err.message);
    }
  }, []);

  useEffect(() => { refresh(); }, [refresh]);

  async function addItem(event) {
    event.preventDefault();
    const response = await fetch('/api/items', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ title }) });
    if (!response.ok) { setError('Could not add item'); return; }
    setTitle('');
    refresh();
  }

  async function removeItem(id) {
    const response = await fetch(`/api/items/${encodeURIComponent(id)}`, { method: 'DELETE' });
    if (response.ok) refresh();
    else setError('Could not delete item');
  }

  return <main>
    <header><div><p className="eyebrow">TASKFLOW</p><h1>Your work, in motion.</h1><p className="subhead">A small, focused place to track what needs doing.</p></div><span className={`health ${health}`}>API {health}</span></header>
    <form onSubmit={addItem}><input aria-label="New task" value={title} onChange={(event) => setTitle(event.target.value)} placeholder="What needs to get done?" maxLength="200" required /><button type="submit">Add task <span>↗</span></button></form>
    {error && <p className="error" role="alert">{error}</p>}
    <section><div className="section-title"><h2>Tasks</h2><span>{items.length} {items.length === 1 ? 'item' : 'items'}</span></div>
      {items.length ? <ul>{items.map((item) => <li key={item.id}><span className="dot" /><span className="item-title">{item.title}</span><button className="delete" onClick={() => removeItem(item.id)} aria-label={`Delete ${item.title}`}>×</button></li>)}</ul> : <div className="empty"><span className="empty-icon">✓</span><p>Nothing on the list yet.</p><small>Add a task above to get started.</small></div>}
    </section>
    <footer>Simple work. Clear next steps.</footer>
  </main>;
}
