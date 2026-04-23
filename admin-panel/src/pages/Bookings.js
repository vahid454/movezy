import React, { useState, useEffect } from 'react';
import api from '../utils/api';

const STATUS_COLORS = { searching: 'searching', accepted: 'accepted', in_progress: 'in_progress', completed: 'completed', cancelled: 'cancelled' };

export default function Bookings() {
  const [bookings, setBookings] = useState([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(1);
  const [statusFilter, setStatusFilter] = useState('');
  const [selected, setSelected] = useState(null);

  useEffect(() => {
    setLoading(true);
    api.get('/admin/bookings', { params: { status: statusFilter, page } })
      .then(r => { setBookings(r.data.bookings); setTotal(r.data.total); })
      .finally(() => setLoading(false));
  }, [statusFilter, page]);

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Bookings</h1>
        <p className="page-subtitle">{total} total bookings</p>
      </div>

      <div className="filters-bar">
        <select value={statusFilter} onChange={e => { setStatusFilter(e.target.value); setPage(1); }}>
          <option value="">All Status</option>
          <option value="searching">🔍 Searching</option>
          <option value="accepted">✔️ Accepted</option>
          <option value="in_progress">🚗 In Progress</option>
          <option value="completed">✅ Completed</option>
          <option value="cancelled">❌ Cancelled</option>
        </select>
      </div>

      <div className="card" style={{ padding: 0 }}>
        {loading ? (
          <div className="loading"><div className="spinner"/><span>Loading bookings...</span></div>
        ) : bookings.length === 0 ? (
          <div className="empty-state"><div className="empty-state-icon">📦</div><p>No bookings found</p></div>
        ) : (
          <div className="table-wrapper">
            <table>
              <thead>
                <tr><th>Booking ID</th><th>Customer</th><th>Driver</th><th>Vehicle</th><th>Status</th><th>Fare (Est.)</th><th>Distance</th><th>Date</th><th></th></tr>
              </thead>
              <tbody>
                {bookings.map(b => (
                  <tr key={b._id} style={{ cursor: 'pointer' }} onClick={() => setSelected(b)}>
                    <td style={{ fontFamily: 'monospace', fontWeight: 700, color: 'var(--primary)' }}>{b.bookingId}</td>
                    <td>
                      <div style={{ fontWeight: 600 }}>{b.customer?.name || '—'}</div>
                      <div style={{ fontSize: 11, color: 'var(--text-secondary)' }}>{b.customer?.phone}</div>
                    </td>
                    <td>
                      {b.driver ? (
                        <>
                          <div style={{ fontWeight: 600 }}>{b.driver.name}</div>
                          <div style={{ fontSize: 11, color: 'var(--text-secondary)' }}>{b.driver.vehicleNumber}</div>
                        </>
                      ) : <span style={{ color: 'var(--text-secondary)' }}>—</span>}
                    </td>
                    <td style={{ textTransform: 'capitalize' }}>{b.vehicleType?.replace('_', ' ')}</td>
                    <td><span className={`badge badge-${STATUS_COLORS[b.status]}`}>{b.status?.replace('_', ' ')}</span></td>
                    <td style={{ fontWeight: 600 }}>₹{b.estimatedFare || '—'}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{b.estimatedDistance ? `${b.estimatedDistance} km` : '—'}</td>
                    <td style={{ color: 'var(--text-secondary)', fontSize: 12 }}>{new Date(b.createdAt).toLocaleDateString('en-IN')}</td>
                    <td><button className="btn btn-ghost btn-sm" onClick={e => { e.stopPropagation(); setSelected(b); }}>Details</button></td>
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

      {selected && (
        <div className="modal-overlay" onClick={() => setSelected(null)}>
          <div className="modal" style={{ maxWidth: 560 }} onClick={e => e.stopPropagation()}>
            <div className="modal-title">📦 Booking Details</div>
            <div style={{ fontSize: 20, fontWeight: 700, color: 'var(--primary)', marginBottom: 12 }}>{selected.bookingId}</div>
            <div className="info-row"><span className="info-label">Status</span><span className={`badge badge-${selected.status}`}>{selected.status?.replace('_', ' ')}</span></div>
            <div className="info-row"><span className="info-label">Vehicle Type</span><span style={{ textTransform: 'capitalize' }}>{selected.vehicleType?.replace('_', ' ')}</span></div>
            <div className="info-row"><span className="info-label">Customer</span><span>{selected.customer?.name} ({selected.customer?.phone})</span></div>
            <div className="info-row"><span className="info-label">Driver</span><span>{selected.driver ? `${selected.driver.name} · ${selected.driver.vehicleNumber}` : 'Not assigned'}</span></div>
            <div className="info-row"><span className="info-label">Pickup</span><span style={{ fontSize: 13 }}>{selected.pickup?.address}</span></div>
            <div className="info-row"><span className="info-label">Drop-off</span><span style={{ fontSize: 13 }}>{selected.dropoff?.address}</span></div>
            <div className="info-row"><span className="info-label">Est. Distance</span><span>{selected.estimatedDistance} km</span></div>
            <div className="info-row"><span className="info-label">Est. Fare</span><span style={{ fontWeight: 700 }}>₹{selected.estimatedFare}</span></div>
            {selected.description && <div className="info-row"><span className="info-label">Description</span><span>{selected.description}</span></div>}
            {selected.cancellationReason && <div className="info-row"><span className="info-label">Cancel Reason</span><span style={{ color: 'var(--danger)' }}>{selected.cancellationReason}</span></div>}
            {selected.customerRating && <div className="info-row"><span className="info-label">Customer Rating</span><span>{'⭐'.repeat(selected.customerRating)} ({selected.customerRating}/5)</span></div>}
            <div className="info-row"><span className="info-label">Created</span><span>{new Date(selected.createdAt).toLocaleString('en-IN')}</span></div>
            {selected.completedAt && <div className="info-row"><span className="info-label">Completed</span><span>{new Date(selected.completedAt).toLocaleString('en-IN')}</span></div>}
            <div className="modal-actions">
              <button className="btn btn-ghost" onClick={() => setSelected(null)}>Close</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
