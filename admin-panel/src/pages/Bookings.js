import React, { useState, useEffect } from 'react';
import { useSearchParams } from 'react-router-dom';
import api from '../utils/api';

const STATUS_COLORS = {
  searching: 'searching',
  accepted: 'accepted',
  driver_arriving: 'driver_arriving',
  in_progress: 'in_progress',
  completed: 'completed',
  cancelled: 'cancelled'
};

export default function Bookings() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [bookings, setBookings] = useState([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(1);
  const [statusFilter, setStatusFilter] = useState('');
  const [q, setQ] = useState(() => searchParams.get('q') || '');
  const [selected, setSelected] = useState(null);
  const [adminCancelReason, setAdminCancelReason] = useState('');
  const [adminCancelLoading, setAdminCancelLoading] = useState(false);

  useEffect(() => {
    const urlQ = searchParams.get('q') || '';
    setQ(urlQ);
  }, [searchParams]);

  useEffect(() => {
    setLoading(true);
    const urlQ = (searchParams.get('q') || '').trim();
    const localQ = q.trim();
    const trimmed = localQ.length >= 2 ? localQ : urlQ.length >= 2 ? urlQ : '';
    const params = { status: statusFilter, page };
    if (trimmed.length >= 2) params.q = trimmed;
    api.get('/admin/bookings', { params })
      .then(r => { setBookings(r.data.bookings); setTotal(r.data.total); })
      .finally(() => setLoading(false));
  }, [statusFilter, page, q, searchParams]);

  const syncQToUrl = (next) => {
    setQ(next);
    setPage(1);
    const sp = new URLSearchParams(searchParams);
    if (next.trim().length >= 2) sp.set('q', next.trim());
    else sp.delete('q');
    setSearchParams(sp, { replace: true });
  };

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Bookings</h1>
        <p className="page-subtitle">{total} total bookings</p>
      </div>

      <div className="filters-bar" style={{ display: 'flex', flexWrap: 'wrap', gap: 12, alignItems: 'center' }}>
        <input
          type="search"
          className="admin-search-input"
          style={{ maxWidth: 280, flex: '1 1 200px' }}
          placeholder="Search booking ID, phone, address, vehicle…"
          value={q}
          onChange={e => syncQToUrl(e.target.value)}
        />
        <select value={statusFilter} onChange={e => { setStatusFilter(e.target.value); setPage(1); }}>
          <option value="">All Status</option>
          <option value="searching">🔍 Searching</option>
          <option value="accepted">✔️ Accepted</option>
          <option value="driver_arriving">🛻 Driver arriving</option>
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
                <tr><th>Booking ID</th><th>Customer</th><th>Driver</th><th>Driver phone</th><th>Vehicle</th><th>Status</th><th>Fare</th><th>Platform / Driver</th><th>Distance</th><th>Date</th><th></th></tr>
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
                    <td style={{ fontSize: 12, fontFamily: 'monospace', color: 'var(--text-secondary)' }}>
                      {b.driver?.phone || '—'}
                    </td>
                    <td style={{ textTransform: 'capitalize' }}>{b.vehicleType?.replace('_', ' ')}</td>
                    <td><span className={`badge badge-${STATUS_COLORS[b.status] || b.status}`}>{b.status?.replace('_', ' ')}</span></td>
                    <td style={{ fontWeight: 600 }}>₹{b.estimatedFare ?? '—'}</td>
                    <td style={{ fontSize: 12, color: 'var(--text-secondary)' }}>
                      {b.platformFee != null ? (
                        <>₹{b.platformFee} / ₹{b.driverPayout ?? '—'}</>
                      ) : '—'}
                    </td>
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
            <div className="info-row"><span className="info-label">Status</span><span className={`badge badge-${STATUS_COLORS[selected.status] || selected.status}`}>{selected.status?.replace('_', ' ')}</span></div>
            <div className="info-row"><span className="info-label">Vehicle Type</span><span style={{ textTransform: 'capitalize' }}>{selected.vehicleType?.replace('_', ' ')}</span></div>
            <div className="info-row"><span className="info-label">Customer</span><span>{selected.customer?.name} ({selected.customer?.phone})</span></div>
            <div className="info-row"><span className="info-label">Driver</span><span>{selected.driver ? `${selected.driver.name} · ${selected.driver.vehicleNumber}` : 'Not assigned'}</span></div>
            {selected.driver?.phone && (
              <div className="info-row"><span className="info-label">Driver phone</span><span style={{ fontFamily: 'monospace', fontWeight: 600 }}>{selected.driver.phone}</span></div>
            )}
            {(selected.platformFee != null || selected.driverPayout != null) && (
              <div className="info-row"><span className="info-label">Commission split</span><span>Platform ₹{selected.platformFee ?? '—'} · Driver ₹{selected.driverPayout ?? '—'} ({selected.platformFeeStatus || '—'})</span></div>
            )}
            <div className="info-row"><span className="info-label">Pickup</span><span style={{ fontSize: 13 }}>{selected.pickup?.address}</span></div>
            <div className="info-row"><span className="info-label">Drop-off</span><span style={{ fontSize: 13 }}>{selected.dropoff?.address}</span></div>
            <div className="info-row"><span className="info-label">Est. Distance</span><span>{selected.estimatedDistance} km</span></div>
            <div className="info-row"><span className="info-label">Est. Fare</span><span style={{ fontWeight: 700 }}>₹{selected.estimatedFare}</span></div>
            {selected.description && <div className="info-row"><span className="info-label">Description</span><span>{selected.description}</span></div>}
            {selected.cancellationReason && <div className="info-row"><span className="info-label">Cancel Reason</span><span style={{ color: 'var(--danger)' }}>{selected.cancellationReason}</span></div>}
            {selected.customerRating && <div className="info-row"><span className="info-label">Customer Rating</span><span>{'⭐'.repeat(selected.customerRating)} ({selected.customerRating}/5)</span></div>}
            <div className="info-row"><span className="info-label">Created</span><span>{new Date(selected.createdAt).toLocaleString('en-IN')}</span></div>
            {selected.completedAt && <div className="info-row"><span className="info-label">Completed</span><span>{new Date(selected.completedAt).toLocaleString('en-IN')}</span></div>}
            {selected.status !== 'completed' && selected.status !== 'cancelled' && (
              <div style={{ marginTop: 16, paddingTop: 16, borderTop: '1px solid var(--border)' }}>
                <div style={{ fontWeight: 700, fontSize: 13, marginBottom: 8 }}>Admin: cancel this trip</div>
                <p style={{ fontSize: 12, color: 'var(--text-secondary)', marginBottom: 10 }}>
                  Cancels immediately for customer and driver (use for stuck jobs or disputes).
                </p>
                <input
                  type="text"
                  className="admin-search-input"
                  style={{ marginBottom: 10 }}
                  placeholder="Reason (shown on booking)…"
                  value={adminCancelReason}
                  onChange={e => setAdminCancelReason(e.target.value)}
                />
                <button
                  type="button"
                  className="btn btn-danger btn-sm"
                  disabled={adminCancelLoading}
                  onClick={async () => {
                    if (!window.confirm('Cancel this booking for everyone? This cannot be undone.')) return;
                    setAdminCancelLoading(true);
                    try {
                      await api.post(`/admin/booking/${selected._id}/cancel`, {
                        reason: adminCancelReason.trim() || 'Cancelled by admin'
                      });
                      setSelected(null);
                      setAdminCancelReason('');
                      const urlQ = (searchParams.get('q') || '').trim();
                      const params = { status: statusFilter, page };
                      const localQ = q.trim();
                      const trimmed = localQ.length >= 2 ? localQ : urlQ.length >= 2 ? urlQ : '';
                      if (trimmed.length >= 2) params.q = trimmed;
                      const r = await api.get('/admin/bookings', { params });
                      setBookings(r.data.bookings);
                      setTotal(r.data.total);
                    } catch (e) {
                      window.alert(e.response?.data?.error || e.message || 'Cancel failed');
                    } finally {
                      setAdminCancelLoading(false);
                    }
                  }}
                >
                  {adminCancelLoading ? 'Cancelling…' : 'Cancel booking'}
                </button>
              </div>
            )}
            <div className="modal-actions">
              <button className="btn btn-ghost" onClick={() => { setSelected(null); setAdminCancelReason(''); }}>Close</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
