import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import api from '../utils/api';

export default function Login() {
  const [secretKey, setSecretKey] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const handleLogin = async (e) => {
    e.preventDefault();
    setLoading(true); setError('');
    try {
      const { data } = await api.post('/auth/admin-login', { secretKey });
      localStorage.setItem('adminToken', data.token);
      navigate('/');
    } catch (err) {
      setError(err.response?.data?.error || 'Login failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="login-logo">
          <div className="logo-big">⚡</div>
          <h1>Movezy</h1>
          <p>Admin Control Panel</p>
        </div>
        {error && <div className="error-msg">⚠️ {error}</div>}
        <form onSubmit={handleLogin}>
          <div className="form-group">
            <label>Admin Secret Key</label>
            <input
              type="password"
              placeholder="Enter secret key..."
              value={secretKey}
              onChange={e => setSecretKey(e.target.value)}
              required
            />
          </div>
          <button type="submit" className="btn btn-primary" style={{ width: '100%', justifyContent: 'center', padding: '12px' }} disabled={loading}>
            {loading ? 'Logging in...' : '🔐 Login to Dashboard'}
          </button>
        </form>
        <p style={{ textAlign: 'center', color: 'var(--text-secondary)', fontSize: '12px', marginTop: '20px' }}>
          Default dev key: <code style={{ color: 'var(--primary)' }}>your_admin_setup_secret</code>
        </p>
      </div>
    </div>
  );
}
