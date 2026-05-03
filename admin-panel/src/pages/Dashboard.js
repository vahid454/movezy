import React, { useState, useEffect } from 'react';
import { Line, Doughnut } from 'react-chartjs-2';
import { Chart as ChartJS, CategoryScale, LinearScale, PointElement, LineElement, ArcElement, Tooltip, Legend, Filler } from 'chart.js';
import api from '../utils/api';

ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, ArcElement, Tooltip, Legend, Filler);

const StatCard = ({ label, value, icon, color, sub }) => (
  <div className="stat-card" style={{ '--accent': color }}>
    <div className="stat-label">{label}</div>
    <div className="stat-value">{value}</div>
    {sub && <div className="stat-sub">{sub}</div>}
    <div className="stat-icon">{icon}</div>
  </div>
);

export default function Dashboard() {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api.get('/admin/dashboard').then(r => { setData(r.data); setLoading(false); }).catch(() => setLoading(false));
    const interval = setInterval(() => {
      api.get('/admin/dashboard').then(r => setData(r.data)).catch(() => {});
    }, 30000);
    return () => clearInterval(interval);
  }, []);

  if (loading) return <div className="loading"><div className="spinner"/><span>Loading dashboard...</span></div>;
  if (!data) return <div className="empty-state"><div className="empty-state-icon">⚠️</div><p>Failed to load dashboard</p></div>;

  const { stats, charts, live } = data;

  const lineData = {
    labels: charts.bookingsByDay.map(d => new Date(d._id).toLocaleDateString('en-IN', { month: 'short', day: 'numeric' })),
    datasets: [{
      label: 'Bookings',
      data: charts.bookingsByDay.map(d => d.count),
      borderColor: '#FF6B00',
      backgroundColor: 'rgba(255,107,0,0.1)',
      fill: true,
      tension: 0.4,
      pointBackgroundColor: '#FF6B00',
    }]
  };

  const typeColors = ['#FF6B00','#3B82F6','#22C55E','#F59E0B','#8B5CF6','#EC4899'];
  const donutData = {
    labels: charts.vehicleDistribution.map(d => d._id?.toUpperCase()),
    datasets: [{
      data: charts.vehicleDistribution.map(d => d.count),
      backgroundColor: typeColors,
      borderColor: '#1A1A1A',
      borderWidth: 2,
    }]
  };

  const chartOpts = {
    responsive: true,
    plugins: { legend: { labels: { color: '#999', font: { family: 'Space Grotesk' } } } },
    scales: { x: { ticks: { color: '#666' }, grid: { color: '#2E2E2E' } }, y: { ticks: { color: '#666' }, grid: { color: '#2E2E2E' } } }
  };

  const donutOpts = {
    responsive: true,
    plugins: { legend: { labels: { color: '#999', font: { family: 'Space Grotesk' } } } }
  };

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Dashboard</h1>
        <p className="page-subtitle">Real-time overview of your Movezy platform</p>
      </div>

      <div className="stats-grid">
        <StatCard label="Total Customers" value={stats.totalUsers.toLocaleString()} icon="👥" color="#3B82F6" />
        <StatCard label="Total Drivers" value={stats.totalDrivers.toLocaleString()} icon="🚗" color="#22C55E" sub={`${stats.approvedDrivers} approved`} />
        <StatCard label="Pending Approval" value={stats.pendingDrivers} icon="⏳" color="#F59E0B" sub="Needs review" />
        <StatCard label="Drivers Online" value={stats.onlineDrivers.toLocaleString()} icon="🟢" color="#22C55E" sub={`${stats.availableDrivers} available`} />
        <StatCard label="Active Trips" value={stats.activeBookings} icon="📦" color="#FF6B00" />
        <StatCard label="Searching Jobs" value={stats.searchingBookings} icon="📡" color="#3B82F6" />
        <StatCard label="Total Bookings" value={stats.totalBookings.toLocaleString()} icon="📋" color="#8B5CF6" />
        <StatCard label="Completed Trips" value={stats.completedBookings.toLocaleString()} icon="✅" color="#22C55E" sub={`${stats.completedToday} today`} />
        <StatCard label="Cancelled Today" value={stats.cancelledToday.toLocaleString()} icon="⚠️" color="#EF4444" />
      </div>

      <div className="charts-grid">
        <div className="card">
          <div className="card-title">📈 Bookings (Last 7 Days)</div>
          {charts.bookingsByDay.length > 0
            ? <Line data={lineData} options={chartOpts} />
            : <div className="empty-state"><div className="empty-state-icon">📊</div><p>No data yet</p></div>
          }
        </div>
        <div className="card">
          <div className="card-title">🚛 Vehicle Type Distribution</div>
          {charts.vehicleDistribution.length > 0
            ? <div style={{ maxWidth: 300, margin: '0 auto' }}><Doughnut data={donutData} options={donutOpts} /></div>
            : <div className="empty-state"><div className="empty-state-icon">🚗</div><p>No data yet</p></div>
          }
        </div>
      </div>

      {stats.pendingDrivers > 0 && (
        <div className="card" style={{ borderColor: '#F59E0B', background: 'rgba(245,158,11,0.05)' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <div>
              <div style={{ fontWeight: 700, fontSize: 16 }}>⚠️ {stats.pendingDrivers} Driver{stats.pendingDrivers > 1 ? 's' : ''} Awaiting Approval</div>
              <div style={{ color: 'var(--text-secondary)', fontSize: 13, marginTop: 4 }}>Review their documents and approve or reject their applications.</div>
            </div>
            <a href="/drivers?status=pending" className="btn btn-primary" style={{ textDecoration: 'none' }}>Review Now →</a>
          </div>
        </div>
      )}

      <div className="live-grid">
        <div className="card">
          <div className="card-title">🚚 Live trips</div>
          {live?.bookings?.length ? (
            <div className="live-list">
              {live.bookings.map(booking => (
                <div className="live-item" key={booking.id}>
                  <div>
                    <div className="live-title-row">
                      <span style={{ fontWeight: 700, color: 'var(--primary)' }}>{booking.bookingId}</span>
                      <span className={`badge badge-${STATUS_COLORS[booking.status] || booking.status}`}>
                        {booking.status?.replace('_', ' ')}
                      </span>
                    </div>
                    <div className="live-meta">{booking.customer?.name || 'Unknown customer'} • {booking.vehicleType?.replace('_', ' ')}</div>
                    <div className="live-sub">{booking.pickup} → {booking.dropoff}</div>
                    {booking.driver?.phone && (
                      <div className="live-sub" style={{ fontWeight: 600, color: 'var(--primary)', marginTop: 4 }}>
                        Driver {booking.driver.phone}
                      </div>
                    )}
                  </div>
                  <div style={{ textAlign: 'right' }}>
                    <div style={{ fontWeight: 700 }}>₹{booking.estimatedFare || 0}</div>
                    {booking.platformFee != null && (
                      <div className="live-meta" style={{ fontSize: 11 }}>
                        Fee ₹{booking.platformFee} · Payout ₹{booking.driverPayout ?? '—'}
                      </div>
                    )}
                    <div className="live-meta">
                      {new Date(booking.updatedAt).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' })}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="empty-state"><div className="empty-state-icon">🛰️</div><p>No active bookings right now</p></div>
          )}
        </div>

        <div className="card">
          <div className="card-title">🛰️ Online Drivers</div>
          {live?.drivers?.length ? (
            <div className="live-list">
              {live.drivers.map(driver => (
                <div className="live-item" key={driver.id}>
                  <div>
                    <div className="live-title-row">
                      <span style={{ fontWeight: 700 }}>{driver.name}</span>
                      <span className={`badge badge-${driver.isAvailable ? 'online' : 'accepted'}`}>
                        {driver.isAvailable ? 'available' : 'on trip'}
                      </span>
                    </div>
                    <div className="live-meta">{driver.vehicleNumber} • {driver.vehicleType?.replace('_', ' ')}</div>
                    <div className="live-sub">⭐ {driver.rating?.toFixed?.(1) ?? driver.rating} • {driver.phone}</div>
                  </div>
                  <div className="live-meta" style={{ textAlign: 'right' }}>
                    {driver.lastSeen
                      ? new Date(driver.lastSeen).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' })
                      : 'Live'}
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="empty-state"><div className="empty-state-icon">🚗</div><p>No drivers online</p></div>
          )}
        </div>
      </div>
    </div>
  );
}

const STATUS_COLORS = {
  searching: 'searching',
  accepted: 'accepted',
  driver_arriving: 'driver_arriving',
  in_progress: 'in_progress',
  completed: 'completed',
  cancelled: 'cancelled'
};
