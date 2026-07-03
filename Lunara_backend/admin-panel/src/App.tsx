import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Toaster } from 'react-hot-toast';
import 'bootstrap/dist/css/bootstrap.min.css';
import { ProtectedRoute } from './components/ProtectedRoute';
import DashboardLayout from './components/DashboardLayout';
import { Login } from './pages/Login';
import { Dashboard } from './pages/Dashboard';
import { Users } from './pages/Users';
import { Venues } from './pages/Venues';
import Ads from './pages/Ads';
import { Bookings } from './pages/Bookings';
import LargePartyRequests from './pages/LargePartyRequests';
import { Analytics } from './pages/Analytics';
import { Compliance } from './pages/Compliance';
import StrangersMeet from './pages/StrangersMeet';
import { HelpCenter } from './pages/HelpCenter';
import { CommunityGuidelines } from './pages/CommunityGuidelines';
import { LegalTerms } from './pages/LegalTerms';
import { ThemeProvider, useThemeMode } from './context/ThemeContext';

// Create React Query client
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchOnWindowFocus: false,
      retry: 1,
    },
  },
});

function AppContent() {
  const { mode } = useThemeMode();

  return (
    <>
      <Toaster
        position="top-right"
        toastOptions={{
          style: {
            background: mode === 'dark' ? '#1a1d26' : '#ffffff',
            color: mode === 'dark' ? '#d4d5d9' : '#1a1d21',
            border: `1px solid ${mode === 'dark' ? 'rgba(255,255,255,0.06)' : '#e9edf4'}`,
            borderRadius: '8px',
            fontSize: '0.8125rem',
            fontFamily: "'Space Grotesk', system-ui, sans-serif",
          },
          success: {
            iconTheme: {
              primary: '#26bf94',
              secondary: '#fff',
            },
          },
          error: {
            iconTheme: {
              primary: '#e6533c',
              secondary: '#fff',
            },
          },
        }}
      />
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route
            path="/"
            element={
              <ProtectedRoute>
                <DashboardLayout />
              </ProtectedRoute>
            }
          >
            <Route index element={<Dashboard />} />
            <Route path="users" element={<Users />} />
            <Route path="venues" element={<Venues />} />
            <Route path="ads" element={<Ads />} />
            <Route path="bookings" element={<Bookings />} />
            <Route path="party-requests" element={<LargePartyRequests />} />
            <Route path="analytics" element={<Analytics />} />
            <Route path="compliance" element={<Compliance />} />
            <Route path="strangers-meet" element={<StrangersMeet />} />
            <Route path="help-center" element={<HelpCenter />} />
            <Route path="community-guidelines" element={<CommunityGuidelines />} />
            <Route path="legal-terms" element={<LegalTerms />} />
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </>
  );
}

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <ThemeProvider>
        <AppContent />
      </ThemeProvider>
    </QueryClientProvider>
  );
}

export default App;
