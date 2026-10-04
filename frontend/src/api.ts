export type Note = {
  id: number;
  title: string;
  body: string;
  created_at: string;
};

export type Health = { status: string; version: string; uptime: number };

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, {
    headers: { 'content-type': 'application/json' },
    ...init,
  });
  if (res.status === 204) return undefined as T;
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error ?? `HTTP ${res.status}`);
  return data as T;
}

// All paths are relative. Vite proxies them in dev; nginx proxies them in containers.
export const api = {
  health: () => request<Health>('/health'),
  listNotes: () => request<Note[]>('/api/notes'),
  createNote: (title: string, body: string) =>
    request<Note>('/api/notes', { method: 'POST', body: JSON.stringify({ title, body }) }),
  deleteNote: (id: number) => request<void>(`/api/notes/${id}`, { method: 'DELETE' }),
};
