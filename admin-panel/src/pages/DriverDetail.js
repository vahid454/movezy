import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import api from '../utils/api';

export default function DriverDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const [driver, setDriver] = useState(null);
  const [bookings, setBookings] = useState([]);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState(false);
  const [showRejectModal, setShowRejectModal] = useState(false);
  const [rejectReason, setRejectReason] = useState('');
  const [toast, setToast] = useState('');

  const load = () => {
    setLoading(true);
    api
      .get(`/admin/driver/${id}`)
      .then((r) => {
        setDriver(r.data.driver);
        setBookings(r.data.bookings || []);
      })
      .finally(() => setLoading(false));
  };

  useEffect(() => { load(); }, [id]);

  const showToast = (msg) => { setToast(msg); setTimeout(() => setToast(''), 3000); };

  const approve = async () => {
    setActionLoading(true);
    try {
      await api.put(`/admin/driver/${id}/approve`);
      showToast('✅ Driver approved and notified!');
      load();
    } catch (e) { showToast('❌ Error: ' + (e.response?.data?.error || e.message)); }
    finally { setActionLoading(false); }
  };

  const reject = async () => {
    if (!rejectReason.trim()) return;
    setActionLoading(true);
    try {
      await api.put(`/admin/driver/${id}/reject`, { reason: rejectReason });
      showToast('Driver rejected.');
      setShowRejectModal(false);
      load();
    } catch (e) { showToast('❌ Error: ' + (e.response?.data?.error || e.message)); }
    finally { setActionLoading(false); }
  };

  if (loading) return <div className="loading"><div className="spinner"/><span>Loading driver...</span></div>;
  if (!driver) return <div className="empty-state"><div className="empty-state-icon">❌</div><p>Driver not found</p></div>;

  const user = driver.user || {};
  const docs = driver.documents || {};
  const resolveDocumentUrl = (value) => {
    if (!value) return '';
    if (/^https?:\/\//i.test(value)) return value;
    if (value.startsWith('/')) return value;
    return `/${value}`;
  };

  return (
    <div>
      {toast && (
        <div style={{ position: 'fixed', top: 24, right: 24, background: 'var(--surface)', border: '1px solid var(--border)', padding: '14px 20px', borderRadius: 10, zIndex: 9999, fontWeight: 600 }}>
          {toast}
        </div>
      )}

      <button className="back-btn" onClick={() => navigate('/drivers')}>← Back to Drivers</button>

      <div className="page-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <div>
          <h1 className="page-title">{driver.name}</h1>
          <p className="page-subtitle">{driver.vehicleNumber} · {driver.vehicleType?.replace('_', ' ').toUpperCase()}</p>
        </div>
        <div style={{ display: 'flex', gap: 10 }}>
          {driver.approvalStatus === 'pending' && (
            <>
              <button className="btn btn-success" onClick={approve} disabled={actionLoading}>✅ Approve</button>
              <button className="btn btn-danger" onClick={() => setShowRejectModal(true)} disabled={actionLoading}>❌ Reject</button>
            </>
          )}
          {driver.approvalStatus === 'approved' && (
            <button className="btn btn-danger" onClick={() => setShowRejectModal(true)} disabled={actionLoading}>⛔ Revoke</button>
          )}
          {driver.approvalStatus === 'rejected' && (
            <button className="btn btn-success" onClick={approve} disabled={actionLoading}>✅ Re-approve</button>
          )}
        </div>
      </div>

      <div className="detail-grid">
        <div>
          <div className="card">
            <div style={{ textAlign: 'center', marginBottom: 20 }}>
              <div className="avatar" style={{ width: 72, height: 72, fontSize: 28, margin: '0 auto 12px' }}>
                {driver.name?.charAt(0)}
              </div>
              <div style={{ fontWeight: 700, fontSize: 18 }}>{driver.name}</div>
              <div style={{ color: 'var(--text-secondary)', fontSize: 13 }}>{driver.phone}</div>
              <div style={{ marginTop: 10 }}>
                <span className={`badge badge-${driver.approvalStatus}`} style={{ fontSize: 13, padding: '6px 14px' }}>
                  {driver.approvalStatus?.toUpperCase()}
                </span>
              </div>
            </div>
            <div className="info-row"><span className="info-label">Status</span><span className={`badge badge-${driver.isOnline ? 'online' : 'offline'}`}>{driver.isOnline ? '● Online' : '○ Offline'}</span></div>
            <div className="info-row"><span className="info-label">Rating</span><span>⭐ {driver.rating?.toFixed(1)}</span></div>
            <div className="info-row"><span className="info-label">Total Trips</span><span>{driver.totalTrips}</span></div>
            <div className="info-row"><span className="info-label">Registered</span><span>{new Date(driver.createdAt).toLocaleDateString('en-IN')}</span></div>
            {driver.reviewedAt && <div className="info-row"><span className="info-label">Reviewed</span><span>{new Date(driver.reviewedAt).toLocaleDateString('en-IN')}</span></div>}
            {driver.rejectionReason && <div className="info-row"><span className="info-label">Reject Reason</span><span style={{ color: 'var(--danger)', fontSize: 12 }}>{driver.rejectionReason}</span></div>}
          </div>
        </div>

        <div>
          <div className="card">
            <div className="card-title">📋 Vehicle & License Details</div>
            <div className="info-row"><span className="info-label">Driving License</span><span>{driver.drivingLicense}</span></div>
            <div className="info-row"><span className="info-label">Vehicle Number</span><span style={{ fontWeight: 700, letterSpacing: 1 }}>{driver.vehicleNumber}</span></div>
            <div className="info-row"><span className="info-label">Vehicle Type</span><span style={{ textTransform: 'capitalize' }}>{driver.vehicleType?.replace('_', ' ')}</span></div>
            {driver.vehicleModel && <div className="info-row"><span className="info-label">Vehicle Model</span><span>{driver.vehicleModel}</span></div>}
          </div>

          <div className="card">
            <div className="card-title">📎 Uploaded Documents</div>
            <div className="doc-grid">
              {[
                { key: 'licenseImage', label: '🪪 Driving License' },
                { key: 'vehicleRC', label: '📄 Vehicle RC' },
                { key: 'insurance', label: '🛡️ Insurance' },
                { key: 'profilePhoto', label: '📷 Profile Photo' }
              ].map(({ key, label }) => (
                <div className="doc-item" key={key}>
                  <div style={{ marginBottom: 6, fontWeight: 600 }}>{label}</div>
                  {docs[key]
                    ? <a href={resolveDocumentUrl(docs[key])} target="_blank" rel="noreferrer">View Document →</a>
                    : <span style={{ color: 'var(--text-secondary)', fontSize: 12 }}>Not uploaded</span>
                  }
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      <div className="card" style={{ marginTop: 20, padding: 0 }}>
        <div className="card-title" style={{ padding: '16px 20px 0' }}>
          📦 Trips & bookings ({bookings.length} recent)
        </div>
        {bookings.length === 0 ? (
          <div className="empty-state" style={{ padding: 32 }}>
            <div className="empty-state-icon">📭</div>
            <p>No bookings for this driver yet</p>
          </div>
        ) : (
          <div className="table-wrapper">
            <table>
              <thead>
                <tr>
                  <th>Booking ID</th>
                  <th>Status</th>
                  <th>Customer</th>
                  <th>Fare</th>
                  <th>Date</th>
                </tr>
              </thead>
              <tbody>
                {bookings.map((b) => (
                  <tr key={b._id}>
                    <td style={{ fontFamily: 'monospace', fontWeight: 700, color: 'var(--primary)' }}>{b.bookingId}</td>
                    <td>
                      <span className={`badge badge-${b.status}`}>{b.status?.replace('_', ' ')}</span>
                    </td>
                    <td>
                      {b.customer ? (
                        <>
                          <div style={{ fontWeight: 600 }}>{b.customer.name}</div>
                          <div style={{ fontSize: 11, color: 'var(--text-secondary)' }}>{b.customer.phone}</div>
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

      {showRejectModal && (
        <div className="modal-overlay" onClick={() => setShowRejectModal(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <div className="modal-title">❌ Reject Driver</div>
            <p style={{ color: 'var(--text-secondary)', fontSize: 13, marginBottom: 16 }}>Please provide a reason. The driver will be notified.</p>
            <div className="form-group">
              <label>Rejection Reason</label>
              <textarea rows={3} placeholder="e.g. Documents not clear, Invalid license number..." value={rejectReason} onChange={e => setRejectReason(e.target.value)} />
            </div>
            <div className="modal-actions">
              <button className="btn btn-ghost" onClick={() => setShowRejectModal(false)}>Cancel</button>
              <button className="btn btn-danger" onClick={reject} disabled={actionLoading || !rejectReason.trim()}>
                {actionLoading ? 'Rejecting...' : 'Reject Driver'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
