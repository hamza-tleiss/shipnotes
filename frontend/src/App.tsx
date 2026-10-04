import { useEffect, useState, type FormEvent } from 'react';
import { api, type Health, type Note } from './api';

export function App() {
  const [notes, setNotes] = useState<Note[]>([]);
  const [health, setHealth] = useState<Health | null>(null);
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  async function refresh() {
    try {
      const [h, list] = await Promise.all([api.health(), api.listNotes()]);
      setHealth(h);
      setNotes(list);
      setError(null);
    } catch (err) {
      setHealth(null);
      setError(err instanceof Error ? err.message : 'API unreachable');
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    refresh();
    const id = setInterval(refresh, 10_000);
    return () => clearInterval(id);
  }, []);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    if (!title.trim()) return;
    try {
      await api.createNote(title.trim(), body);
      setTitle('');
      setBody('');
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'failed to create');
    }
  }

  async function onDelete(id: number) {
    try {
      await api.deleteNote(id);
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'failed to delete');
    }
  }

  return (
    <main className="container">
      <header className="header">
        <h1>ShipNotes</h1>
        <span className={`badge ${health ? 'badge-up' : 'badge-down'}`}>
          {health ? `API ${health.version} · up ${health.uptime}s` : 'API down'}
        </span>
      </header>

      <form className="card form" onSubmit={onSubmit}>
        <input
          placeholder="Title"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          maxLength={200}
          required
        />
        <textarea
          placeholder="What did you ship today?"
          value={body}
          onChange={(e) => setBody(e.target.value)}
          rows={3}
        />
        <button type="submit">Add note</button>
      </form>

      {error && <p className="error">{error}</p>}
      {loading && <p className="muted">Loading…</p>}

      <ul className="list">
        {notes.map((n) => (
          <li key={n.id} className="card">
            <div className="note-head">
              <strong>{n.title}</strong>
              <button className="ghost" onClick={() => onDelete(n.id)} aria-label="delete">
                ×
              </button>
            </div>
            {n.body && <p>{n.body}</p>}
            <time className="muted">{new Date(n.created_at).toLocaleString()}</time>
          </li>
        ))}
        {!loading && notes.length === 0 && <p className="muted">No notes yet.</p>}
      </ul>
    </main>
  );
}
