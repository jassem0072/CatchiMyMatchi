import axios from 'axios';
import { clearAuthStorage, readStoredToken } from '../authStorage';

const client = axios.create({ baseURL: '/api' });

client.interceptors.request.use((cfg) => {
  const token = readStoredToken();
  if (token && cfg.headers) {
    cfg.headers.Authorization = `Bearer ${token}`;
  }
  return cfg;
});

client.interceptors.response.use(
  (r) => r,
  (err) => {
    if (err.response?.status === 401) {
      clearAuthStorage();
      window.location.href = '/login';
    }
    return Promise.reject(err);
  },
);

export default client;
