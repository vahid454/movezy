import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import api from '../utils/api';

const STATUS_BADGE = {
  searching: 'searching',
  accepted: 'accepted',
  driver_arriving: 'driver_arriving',
  in_progress: 'in_progress',
  completed: 'completed',
  cancelled: 'cancelled'
};

export default function CustomerDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const [user, setUser] = useState(null);
  const [bookings, setBookings] = useState([]);
  const [loading, setLoading] = useState(true);
  const [toast, setToast] = useState('');
  const [actionLoading, setActionLoading] = useState(false);

  const load = () => {
    setLoading(true);
    api
      .get(`/admin/user/${id}`)
      .then((r) => {
        setUser(r.data.user);
        setBookings(r.data.bookings || []);
      })
      .catch(() => {
        setUser(null);
        setBookings([]);
      })
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [id]);

  const showToast = (msg) => {
    setToast(msg);
    setTimeout(() => setToast(''), 3000);
  };

  const toggle = async () => {
    if (!user) return;
    setActionLoading(true);
    try {
      await api.put(`/admin/user/${user._id}/toggle`);
      showToast(user.isActive ? 'Customer blocked' : 'Customer unblocked');
      load();
    } catch (e) {
      showToast('Error: ' + (e.response?.data?.error || e.message));
    } finally {
      setActionLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="loading">
        <div className="spinner" />
        <span>Loading customer…</span>
      </div>
    );
  }
  if (!user) {
    return (
      <div className="empty-state">
        <div className="empty-state-icon">❌</div>
        <p>Customer not found</p>
        <button className="btn btn-ghost" type="button" onClick={() => navigate('/users')}>
          ← Back
        </button>
      </div>
    );
  }

  return (
    <div>
      {toast && (
        <div
          style={{
            position: 'fixed',
            top: 24,
            right: 24,
            background: 'var(--surface)',
            border: '1px solid var(--border)',
            padding: '14px 20px',
            borderRadius: 10,
            zIndex: 9999,
            fontWeight: 600
          }}
        >
          {toast}
        </div>
      )}

      <button className="back-btn" type="button" onClick={() => navigate('/users')}>
        ← Back to Customers
      </button>

      <div
        className="page-header"
        style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: 16 }}
      >
        <div>
          <h1 className="page-title">{user.name}</h1>
          <p className="page-subtitle" style={{ fontFamily: 'monospace' }}>
            {user.phone}
          </p>
        </div>
        <button
          type="button"
          className={`btn btn-sm ${user.isActive ? 'btn-danger' : 'btn-success'}`}
          onClick={toggle}
          disabled={actionLoading}
        >
          {user.isActive ? '🚫 Block customer' : '✅ Unblock customer'}
        </button>
      </div>

      <div className="detail-grid">
        <div className="card">
          <div className="card-title">👤 Profile</div>
          <div className="info-row">
            <span className="info-label">Status</span>
            <span className={`badge ${user.isActive ? 'badge-approved' : 'badge-rejected'}`}>
              {user.isActive ? 'Active' : 'Blocked'}
            </span>
          </div>
          <div className="info-row">
            <span className="info-label">Last seen</span>
            <span>{user.lastSeen ? new Date(user.lastSeen).toLocaleString('en-IN') : '—'}</span>
          </div>
          <div className="info-row">
            <span className="info-label">Joined</span>
            <span>{user.createdAt ? new Date(user.createdAt).toLocaleDateString('en-IN') : '—'}</span>
          </div>
        </div>
      </div>

      <div className="card" style={{ marginTop: 20, padding: 0 }}>
        <div className="card-title" style={{ padding: '16px 20px 0' }}>
          📦 Bookings ({bookings.length} recent)
        </div>
        {bookings.length === 0 ? (
          <div className="empty-state" style={{ padding: 32 }}>
            <div className="empty-state-icon">📭</div>
            <p>No bookings yet</p>
          </div>
        ) : (
          <div className="table-wrapper">
            <table>
              <thead>
                <tr>
                  <th>Booking ID</th>
                  <th>Status</th>
                  <th>Driver</th>
                  <th>Fare</th>
                  <th>Created</th>
                </tr>
              </thead>
              <tbody>
                {bookings.map((b) => (
                  <tr key={b._id}>
                    <td style={{ fontFamily: 'monospace', fontWeight: 700, color: 'var(--primary)' }}>{b.bookingId}</td>
                    <td>
                      <span className={`badge badge-${STATUS_BADGE[b.status] || b.status}`}>
                        {b.status?.replace('_', ' ')}
                      </span>
                    </td>
                    <td>
                      {b.driver ? (
                        <>
                          <div style={{ fontWeight: 600 }}>{b.driver.name}</div>
                          <div style={{ fontSize: 11, color: 'var(--text-secondary)' }}>{b.driver.phone}</div>
                        </>
                      ) : (
                        '—'
                      )}
                    </td>
                    <td>₹{b.estimatedFare ?? '—'}</td>
                    <td style={{ fontSize: 12, color: 'var(--text-secondary)' }}>
                      {b.createdAt ? new Date(b.createdAt).toLocaleDateString('en-IN') : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
