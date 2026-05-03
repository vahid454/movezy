import React, { useState, useEffect } from 'react';
import api from '../utils/api';

export default function Commission() {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api
      .get('/admin/commission-board')
      .then((r) => setData(r.data))
      .catch(() => setData(null))
      .finally(() => setLoading(false));
  }, []);

  if (loading) {
    return (
      <div className="loading">
        <div className="spinner" />
        <span>Loading commission data…</span>
      </div>
    );
  }
  if (!data) {
    return (
      <div className="empty-state">
        <div className="empty-state-icon">⚠️</div>
        <p>Could not load commission board</p>
      </div>
    );
  }

  const { summary, byStatus, last30Days, commissionPercent, activeTrips } = data;

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Commission &amp; revenue</h1>
        <p className="page-subtitle">
          Platform fee on completed trips (default {commissionPercent}% of customer fare when fee
          not stored on older rows). Active trips right now:{' '}
          <strong>{activeTrips}</strong>.
        </p>
      </div>

      <div className="stats-grid">
        <div className="stat-card" style={{ '--accent': '#FF6B00' }}>
          <div className="stat-label">Movezy platform (all time)</div>
          <div className="stat-value">₹{(summary.totalPlatform || 0).toLocaleString('en-IN')}</div>
          <div className="stat-sub">From {summary.trips || 0} completed trips</div>
          <div className="stat-icon">🚚</div>
        </div>
        <div className="stat-card" style={{ '--accent': '#22C55E' }}>
          <div className="stat-label">Driver payouts (est.)</div>
          <div className="stat-value">₹{(summary.totalDriverPayout || 0).toLocaleString('en-IN')}</div>
          <div className="stat-sub">Customer paid − platform fee</div>
          <div className="stat-icon">📦</div>
        </div>
        <div className="stat-card" style={{ '--accent': '#3B82F6' }}>
          <div className="stat-label">Customer GMV (completed)</div>
          <div className="stat-value">₹{(summary.totalCustomerPaid || 0).toLocaleString('en-IN')}</div>
          <div className="stat-sub">Total estimated fares</div>
          <div className="stat-icon">💳</div>
        </div>
      </div>

      <div className="charts-grid" style={{ marginTop: 24 }}>
        <div className="card">
          <div className="card-title">📋 Fee status (completed)</div>
          {byStatus?.length ? (
            <table>
              <thead>
                <tr>
                  <th>Status</th>
                  <th>Trips</th>
                  <th>Platform ₹</th>
                </tr>
              </thead>
              <tbody>
                {byStatus.map((row) => (
                  <tr key={row._id || 'na'}>
                    <td style={{ textTransform: 'capitalize' }}>{row._id || '—'}</td>
                    <td>{row.count}</td>
                    <td style={{ fontWeight: 700 }}>₹{(row.platformTotal || 0).toLocaleString('en-IN')}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <div className="empty-state">
              <div className="empty-state-icon">📭</div>
              <p>No completed bookings yet</p>
            </div>
          )}
        </div>
        <div className="card">
          <div className="card-title">📈 Last 30 days (completed)</div>
          {last30Days?.length ? (
            <div className="table-wrapper">
              <table>
                <thead>
                  <tr>
                    <th>Day</th>
                    <th>Trips</th>
                    <th>Platform ₹</th>
                  </tr>
                </thead>
                <tbody>
                  {last30Days.map((d) => (
                    <tr key={d._id}>
                      <td style={{ fontFamily: 'monospace' }}>{d._id}</td>
                      <td>{d.trips}</td>
                      <td style={{ fontWeight: 600 }}>₹{(d.platformFee || 0).toLocaleString('en-IN')}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <div className="empty-state">
              <div className="empty-state-icon">📊</div>
              <p>No completed trips in the last 30 days</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
