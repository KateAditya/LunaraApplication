import axios, { type AxiosInstance, type InternalAxiosRequestConfig } from 'axios';

const getBaseUrl = (): string => {
    const envUrl = import.meta.env.VITE_API_URL;
    if (envUrl && typeof envUrl === 'string' && envUrl.trim() !== '') {
        return envUrl.trim().replace(/\/+$/, '');
    }
    if (typeof window !== 'undefined' && window.location?.origin) {
        return window.location.origin;
    }
    return 'http://localhost:9076';
};

const API_URL = getBaseUrl();

// Create axios instance
const apiClient: AxiosInstance = axios.create({
    baseURL: API_URL,
    timeout: 30000,          // 30 s for regular API calls
    headers: {
        'Content-Type': 'application/json',
    },
});

// Request interceptor - add auth token + extend timeout for file uploads
apiClient.interceptors.request.use(
    (config: InternalAxiosRequestConfig) => {
        const token = localStorage.getItem('accessToken');
        if (token && config.headers) {
            config.headers.Authorization = `Bearer ${token}`;
        }

        // For multipart/form-data (file uploads), DELETE the Content-Type header so
        // axios sets it automatically with the correct multipart boundary string.
        // Manually setting 'multipart/form-data' strips the boundary and breaks multer.
        if (config.data instanceof FormData) {
            delete config.headers['Content-Type'];
            config.timeout = 5 * 60 * 1000; // 5 minutes for uploads
        }

        return config;
    },
    (error) => {
        return Promise.reject(error);
    }
);

// Response interceptor - unwrap data, handle 401 with token refresh
apiClient.interceptors.response.use(
    (response) => {
        return response.data;
    },
    async (error) => {
        const originalRequest = error.config;

        // Only attempt token refresh on 401 (not on 400, 413, 500, network errors, etc.)
        if (error.response?.status === 401 && !originalRequest._retry) {
            originalRequest._retry = true;

            const refreshToken = localStorage.getItem('refreshToken');
            if (refreshToken) {
                try {
                    // Use raw axios (not apiClient) to avoid double-unwrap from our interceptor
                    const refreshRes = await axios.post(`${API_URL}/api/auth/refresh`, { refreshToken });
                    const newAccessToken: string = refreshRes.data?.accessToken || refreshRes.data?.data?.accessToken;

                    if (!newAccessToken) throw new Error('No access token in refresh response');

                    localStorage.setItem('accessToken', newAccessToken);
                    originalRequest.headers.Authorization = `Bearer ${newAccessToken}`;
                    return apiClient(originalRequest);
                } catch (refreshError) {
                    // Refresh failed — clear tokens and go to login
                    localStorage.removeItem('accessToken');
                    localStorage.removeItem('refreshToken');
                    window.location.href = '/login';
                    return Promise.reject(refreshError);
                }
            } else {
                // No refresh token at all — go to login
                localStorage.removeItem('accessToken');
                window.location.href = '/login';
            }
        }

        // For all other errors (400, 413, 422, 500 …) just reject without redirecting
        return Promise.reject(error);
    }
);

export default apiClient;
