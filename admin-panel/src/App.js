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

const Sidebar = ({ onLogout, theme, onToggleTheme }) => {
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
      <button className="theme-btn" onClick={onToggleTheme} type="button">
        <span>{theme === 'light' ? '🌙' : '☀️'}</span>
        {theme === 'light' ? 'Dark mode' : 'Light mode'}
      </button>
      <button className="logout-btn" onClick={onLogout}>
        <span>🚪</span> Logout
      </button>
    </aside>
  );
};

const Layout = ({ children, theme, onToggleTheme }) => {
  const navigate = useNavigate();
  const handleLogout = () => {
    localStorage.removeItem('adminToken');
    navigate('/login');
  };
  return (
    <div className="app-layout">
      <Sidebar onLogout={handleLogout} theme={theme} onToggleTheme={onToggleTheme} />
      <main className="main-content">
        <div className="topbar">
          <div>
            <div className="topbar-title">Operations Console</div>
            <div className="topbar-subtitle">Movezy live dispatch and booking control</div>
          </div>
          <div className="topbar-theme">{theme === 'light' ? 'Light' : 'Dark'} mode</div>
        </div>
        <div className="content-shell">{children}</div>
      </main>
    </div>
  );
};

export default function App() {
  const [theme, setTheme] = useState(() => localStorage.getItem('adminTheme') || 'light');

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('adminTheme', theme);
  }, [theme]);

  const handleToggleTheme = () => {
    setTheme((currentTheme) => (currentTheme === 'light' ? 'dark' : 'light'));
  };

  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/*" element={
          <PrivateRoute>
            <Layout theme={theme} onToggleTheme={handleToggleTheme}>
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
