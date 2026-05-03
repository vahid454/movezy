// Users.js
import React, { useState, useEffect, useRef } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import api from '../utils/api';

export function Users() {
  const [searchParams, setSearchParams] = useSearchParams();
  const navigate = useNavigate();
  const [users, setUsers] = useState([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(1);
  /** Local draft so single-character search is not wiped when URL omits `q`. */
  const [qLocal, setQLocal] = useState(() => searchParams.get('q') || '');
  const skipNextUrlSync = useRef(false);

  useEffect(() => {
    const ext = searchParams.get('q') || '';
    if (skipNextUrlSync.current) {
      skipNextUrlSync.current = false;
      return;
    }
    if (ext && ext !== qLocal) setQLocal(ext);
  }, [searchParams]);

  const qTrim = qLocal.trim();

  useEffect(() => {
    setLoading(true);
    const params = { page };
    if (qTrim.length >= 1) params.q = qTrim;
    api
      .get('/admin/users', { params })
      .then((r) => {
        setUsers(r.data.users);
        setTotal(r.data.total);
      })
      .finally(() => setLoading(false));
  }, [page, qLocal]);

  const onSearchChange = (next) => {
    setQLocal(next);
    setPage(1);
    const sp = new URLSearchParams(searchParams);
    if (next.trim().length >= 1) sp.set('q', next.trim());
    else sp.delete('q');
    skipNextUrlSync.current = true;
    setSearchParams(sp, { replace: true });
  };

  const toggle = async (id) => {
    await api.put(`/admin/user/${id}/toggle`);
    const params = { page };
    if (qTrim.length >= 1) params.q = qTrim;
    const r = await api.get('/admin/users', { params });
    setUsers(r.data.users);
    setTotal(r.data.total);
  };

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Customers</h1>
        <p className="page-subtitle">{total} registered customers</p>
      </div>
      <div className="filters-bar" style={{ marginBottom: 16 }}>
        <input
          type="search"
          className="admin-search-input"
          style={{ maxWidth: 360 }}
          placeholder="Search by name or phone…"
          value={qLocal}
          onChange={e => onSearchChange(e.target.value)}
        />
      </div>
      <div className="card" style={{ padding: 0 }}>
        {loading ? (
          <div className="loading"><div className="spinner"/><span>Loading...</span></div>
        ) : (
          <div className="table-wrapper">
            <table>
              <thead>
                <tr><th>Customer</th><th>Phone</th><th>Status</th><th>Last Seen</th><th>Joined</th><th>Action</th></tr>
              </thead>
              <tbody>
                {users.map(u => (
                  <tr
                    key={u._id}
                    style={{ cursor: 'pointer' }}
                    onClick={() => navigate(`/users/${u._id}`)}
                  >
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                        <div className="avatar">{u.name?.charAt(0).toUpperCase()}</div>
                        <span style={{ fontWeight: 600 }}>{u.name}</span>
                      </div>
                    </td>
                    <td style={{ color: 'var(--text-secondary)' }}>{u.phone}</td>
                    <td><span className={`badge ${u.isActive ? 'badge-approved' : 'badge-rejected'}`}>{u.isActive ? 'Active' : 'Blocked'}</span></td>
                    <td style={{ color: 'var(--text-secondary)', fontSize: 12 }}>{u.lastSeen ? new Date(u.lastSeen).toLocaleDateString('en-IN') : '—'}</td>
                    <td style={{ color: 'var(--text-secondary)', fontSize: 12 }}>{new Date(u.createdAt).toLocaleDateString('en-IN')}</td>
                    <td onClick={(e) => e.stopPropagation()}>
                      <button className={`btn btn-sm ${u.isActive ? 'btn-danger' : 'btn-success'}`} onClick={() => toggle(u._id)}>
                        {u.isActive ? '🚫 Block' : '✅ Unblock'}
                      </button>
                      <button type="button" className="btn btn-ghost btn-sm" style={{ marginLeft: 8 }} onClick={() => navigate(`/users/${u._id}`)}>
                        View →
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
      {Math.ceil(total / 20) > 1 && (
        <div className="pagination">
          <button onClick={() => setPage(p => p - 1)} disabled={page === 1}>← Prev</button>
          <span style={{ color: 'var(--text-secondary)', fontSize: 13 }}>Page {page} of {Math.ceil(total / 20)}</span>
          <button onClick={() => setPage(p => p + 1)} disabled={page >= Math.ceil(total / 20)}>Next →</button>
        </div>
      )}
    </div>
  );
}

export default Users;
