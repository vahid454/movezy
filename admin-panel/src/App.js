import React, { useState, useEffect } from 'react';
import { BrowserRouter, Routes, Route, Navigate, NavLink, useNavigate } from 'react-router-dom';
import Dashboard from './pages/Dashboard';
import Drivers from './pages/Drivers';
import DriverDetail from './pages/DriverDetail';
import Users from './pages/Users';
import Bookings from './pages/Bookings';
import Login from './pages/Login';
import './App.css';

const PrivateRoute = ({ children }) => {
  const token = localStorage.getItem('adminToken');
  return token ? children : <Navigate to="/login" replace />;
};

const Sidebar = ({ onLogout }) => {
  const navItems = [
    { to: '/', label: 'Dashboard', icon: '📊' },
    { to: '/drivers', label: 'Drivers', icon: '🚗' },
    { to: '/users', label: 'Customers', icon: '👥' },
    { to: '/bookings', label: 'Bookings', icon: '📦' },
  ];

  return (
    <aside className="sidebar">
      <div className="sidebar-logo">
        <span className="logo-icon">⚡</span>
        <span className="logo-text">Movezy</span>
        <span className="logo-badge">Admin</span>
      </div>
      <nav className="sidebar-nav">
        {navItems.map(item => (
          <NavLink key={item.to} to={item.to} end={item.to === '/'} className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}>
            <span className="nav-icon">{item.icon}</span>
            <span className="nav-label">{item.label}</span>
          </NavLink>
        ))}
      </nav>
      <button className="logout-btn" onClick={onLogout}>
        <span>🚪</span> Logout
      </button>
    </aside>
  );
};

const Layout = ({ children }) => {
  const navigate = useNavigate();
  const handleLogout = () => {
    localStorage.removeItem('adminToken');
    navigate('/login');
  };
  return (
    <div className="app-layout">
      <Sidebar onLogout={handleLogout} />
      <main className="main-content">{children}</main>
    </div>
  );
};

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/*" element={
          <PrivateRoute>
            <Layout>
              <Routes>
                <Route path="/" element={<Dashboard />} />
                <Route path="/drivers" element={<Drivers />} />
                <Route path="/drivers/:id" element={<DriverDetail />} />
                <Route path="/users" element={<Users />} />
                <Route path="/bookings" element={<Bookings />} />
              </Routes>
            </Layout>
          </PrivateRoute>
        } />
      </Routes>
    </BrowserRouter>
  );
}
