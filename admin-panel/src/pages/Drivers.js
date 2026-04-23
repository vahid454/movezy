import React, { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import api from '../utils/api';

export default function Drivers() {
  const [drivers, setDrivers] = useState([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(1);
  const [statusFilter, setStatusFilter] = useState('');
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();

  useEffect(() => {
    const s = searchParams.get('status');
    if (s) setStatusFilter(s);
  }, [searchParams]);

  useEffect(() => {
    setLoading(true);
    api.get('/admin/drivers', { params: { status: statusFilter, page } })
      .then(r => { setDrivers(r.data.drivers); setTotal(r.data.total); })
      .finally(() => setLoading(false));
  }, [statusFilter, page]);

  const totalPages = Math.ceil(total / 20);

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Driver Management</h1>
        <p className="page-subtitle">{total} total drivers registered</p>
      </div>

      <div className="filters-bar">
        <select value={statusFilter} onChange={e => { setStatusFilter(e.target.value); setPage(1); }}>
          <option value="">All Status</option>
          <option value="pending">⏳ Pending</option>
          <option value="approved">✅ Approved</option>
          <option value="rejected">❌ Rejected</option>
        </select>
      </div>

      <div className="card" style={{ padding: 0 }}>
        {loading ? (
          <div className="loading"><div className="spinner"/><span>Loading drivers...</span></div>
        ) : drivers.length === 0 ? (
          <div className="empty-state"><div className="empty-state-icon">🚗</div><p>No drivers found</p></div>
        ) : (
          <div className="table-wrapper">
            <table>
              <thead>
                <tr>
                  <th>Driver</th>
                  <th>Phone</th>
                  <th>Vehicle</th>
                  <th>Type</th>
                  <th>Status</th>
                  <th>Online</th>
                  <th>Trips</th>
                  <th>Rating</th>
                  <th>Registered</th>
                  <th>Action</th>
                </tr>
              </thead>
              <tbody>
                {drivers.map(d => (
                  <tr key={d._id} style={{ cursor: 'pointer' }} onClick={() => navigate(`/drivers/${d._id}`)}>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                        <div className="avatar">{d.name?.charAt(0).toUpperCase()}</div>
                        <div>
                          <div style={{ fontWeight: 600 }}>{d.name}</div>
                          <div style={{ fontSize: 11, color: 'var(--text-secondary)' }}>{d.drivingLicense}</div>
                        </div>
                      </div>
                    </td>
                    <td style={{ color: 'var(--text-secondary)' }}>{d.phone}</td>
                    <td style={{ fontWeight: 600, letterSpacing: 1 }}>{d.vehicleNumber}</td>
                    <td style={{ textTransform: 'capitalize' }}>{d.vehicleType?.replace('_', ' ')}</td>
                    <td><span className={`badge badge-${d.approvalStatus}`}>{d.approvalStatus}</span></td>
                    <td><span className={`badge badge-${d.isOnline ? 'online' : 'offline'}`}>{d.isOnline ? '● Online' : '○ Offline'}</span></td>
                    <td>{d.totalTrips}</td>
                    <td>⭐ {d.rating?.toFixed(1)}</td>
                    <td style={{ color: 'var(--text-secondary)', fontSize: 12 }}>{new Date(d.createdAt).toLocaleDateString('en-IN')}</td>
                    <td onClick={e => e.stopPropagation()}>
                      <button className="btn btn-ghost btn-sm" onClick={() => navigate(`/drivers/${d._id}`)}>View →</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {totalPages > 1 && (
        <div className="pagination">
          <button onClick={() => setPage(p => p - 1)} disabled={page === 1}>← Prev</button>
          <span style={{ color: 'var(--text-secondary)', fontSize: 13 }}>Page {page} of {totalPages}</span>
          <button onClick={() => setPage(p => p + 1)} disabled={page === totalPages}>Next →</button>
        </div>
      )}
    </div>
  );
}
