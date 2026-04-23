// Users.js
import React, { useState, useEffect } from 'react';
import api from '../utils/api';

export function Users() {
  const [users, setUsers] = useState([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(1);

  const load = () => {
    setLoading(true);
    api.get('/admin/users', { params: { page } }).then(r => { setUsers(r.data.users); setTotal(r.data.total); }).finally(() => setLoading(false));
  };

  useEffect(() => { load(); }, [page]);

  const toggle = async (id) => {
    await api.put(`/admin/user/${id}/toggle`);
    load();
  };

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Customers</h1>
        <p className="page-subtitle">{total} registered customers</p>
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
                  <tr key={u._id}>
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
                    <td>
                      <button className={`btn btn-sm ${u.isActive ? 'btn-danger' : 'btn-success'}`} onClick={() => toggle(u._id)}>
                        {u.isActive ? '🚫 Block' : '✅ Unblock'}
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
