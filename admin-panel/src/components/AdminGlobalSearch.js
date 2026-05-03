import React, { useState, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import api from '../utils/api';

export default function AdminGlobalSearch() {
  const [q, setQ] = useState('');
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [data, setData] = useState({ users: [], drivers: [], bookings: [] });
  const nav = useNavigate();
  const wrapRef = useRef(null);
  const tRef = useRef(null);

  useEffect(() => {
    const onDoc = (e) => {
      if (wrapRef.current && !wrapRef.current.contains(e.target)) setOpen(false);
    };
    document.addEventListener('mousedown', onDoc);
    return () => document.removeEventListener('mousedown', onDoc);
  }, []);

  useEffect(() => {
    if (tRef.current) clearTimeout(tRef.current);
    const trimmed = q.trim();
    if (trimmed.length < 2) {
      setData({ users: [], drivers: [], bookings: [] });
      setLoading(false);
      return;
    }
    setLoading(true);
    tRef.current = setTimeout(() => {
      api
        .get('/admin/search', { params: { q: trimmed } })
        .then((r) => {
          setData({
            users: r.data.users || [],
            drivers: r.data.drivers || [],
            bookings: r.data.bookings || []
          });
        })
        .catch(() => setData({ users: [], drivers: [], bookings: [] }))
        .finally(() => setLoading(false));
    }, 220);
    return () => {
      if (tRef.current) clearTimeout(tRef.current);
    };
  }, [q]);

  const hasAny =
    data.users.length + data.drivers.length + data.bookings.length > 0;
  const showPanel = open && q.trim().length >= 2;

  return (
    <div className="admin-search-wrap" ref={wrapRef}>
      <input
        type="search"
        className="admin-search-input"
        placeholder="Search phone, name, vehicle, booking ID…"
        value={q}
        onChange={(e) => {
          setQ(e.target.value);
          setOpen(true);
        }}
        onFocus={() => setOpen(true)}
        aria-label="Global search"
      />
      {showPanel && (
        <div className="admin-search-panel">
          {loading && <div className="admin-search-muted">Searching…</div>}
          {!loading && !hasAny && (
            <div className="admin-search-muted">No matches — try another term</div>
          )}
          {!loading && data.bookings.length > 0 && (
            <div className="admin-search-section">
              <div className="admin-search-heading">Bookings</div>
              {data.bookings.map((b) => (
                <button
                  key={b._id}
                  type="button"
                  className="admin-search-row"
                  onClick={() => {
                    setOpen(false);
                    nav(`/bookings?q=${encodeURIComponent(b.bookingId || '')}`);
                  }}
                >
                  <span className="admin-search-title">{b.bookingId}</span>
                  <span className="admin-search-meta">
                    {b.status} · ₹{b.estimatedFare ?? '—'}
                  </span>
                </button>
              ))}
            </div>
          )}
          {!loading && data.drivers.length > 0 && (
            <div className="admin-search-section">
              <div className="admin-search-heading">Drivers</div>
              {data.drivers.map((d) => (
                <button
                  key={d._id}
                  type="button"
                  className="admin-search-row"
                  onClick={() => {
                    setOpen(false);
                    nav(`/drivers/${d._id}`);
                  }}
                >
                  <span className="admin-search-title">{d.name}</span>
                  <span className="admin-search-meta">
                    {d.phone} · {d.vehicleNumber}
                  </span>
                </button>
              ))}
            </div>
          )}
          {!loading && data.users.length > 0 && (
            <div className="admin-search-section">
              <div className="admin-search-heading">Customers</div>
              {data.users.map((u) => (
                <button
                  key={u._id}
                  type="button"
                  className="admin-search-row"
                  onClick={() => {
                    setOpen(false);
                    nav(`/users?q=${encodeURIComponent(u.phone || u.name || '')}`);
                  }}
                >
                  <span className="admin-search-title">{u.name}</span>
                  <span className="admin-search-meta">{u.phone}</span>
                </button>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
