import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Toaster } from 'react-hot-toast';
import 'bootstrap/dist/css/bootstrap.min.css';
import { ProtectedRoute } from './components/ProtectedRoute';
import DashboardLayout from './components/DashboardLayout';
import { Login } from './pages/Login';
import { Dashboard } from './pages/Dashboard';
import { Users } from './pages/Users';
import { AutoblockedUsers } from './pages/AutoblockedUsers';
import { ReportedUsers } from './pages/ReportedUsers';
import { DeletedAccounts } from './pages/DeletedAccounts';
import { Venues } from './pages/Venues';
import Ads from './pages/Ads';
import { Bookings } from './pages/Bookings';
import LargePartyRequests from './pages/LargePartyRequests';
import { Analytics } from './pages/Analytics';
import { Compliance } from './pages/Compliance';
import StrangersMeet from './pages/StrangersMeet';
import { GroupParties } from './pages/GroupParties';
import { HelpCenter } from './pages/HelpCenter';
import { CommunityGuidelines } from './pages/CommunityGuidelines';
import { LegalTerms } from './pages/LegalTerms';
import ChatSettings from './pages/ChatSettings';
import { SubscriptionManagement } from './pages/SubscriptionManagement';
import { SafetyChecks } from './pages/SafetyChecks';
import { Payments } from './pages/Payments';
import { VenueBookingSummary } from './pages/reports/VenueBookingSummary';
import { CancelledPartyPlans } from './pages/CancelledPartyPlans';
import { CancellationAnalytics } from './pages/CancellationAnalytics';
import { WalletManagement } from './pages/WalletManagement';
import { EventBookingPage } from './pages/EventBooking/EventBookingPage';
import { BookingPolicySettings } from './pages/BookingPolicySettings';
import { CancellationRequests } from './pages/CancellationRequests';
import { ThemeProvider, useThemeMode } from './context/ThemeContext';

// Create React Query client with 3-minute smart auto-refresh
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchInterval: 3 * 60 * 1000, // Auto-refresh all pages every 3 minutes
      refetchIntervalInBackground: false, // Freeze polling when tab is hidden to preserve system performance
      refetchOnWindowFocus: true, // Smoothly refresh stale data when admin switches back to tab
      refetchOnReconnect: true, // Auto-refresh when internet reconnects
      staleTime: 45 * 1000, // 45 seconds cache validity to prevent duplicate bursts
      gcTime: 10 * 60 * 1000, // 10 minutes cache garbage collection
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
            <Route path="autoblocked-users" element={<AutoblockedUsers />} />
            <Route path="reported-users" element={<ReportedUsers />} />
            <Route path="deleted-accounts" element={<DeletedAccounts />} />
            <Route path="venues" element={<Venues />} />
            <Route path="ads" element={<Ads />} />
            <Route path="bookings" element={<Bookings />} />
            <Route path="event-bookings" element={<EventBookingPage />} />
            <Route path="party-requests" element={<LargePartyRequests />} />
            <Route path="group-parties" element={<GroupParties />} />
            <Route path="analytics" element={<Analytics />} />
            <Route path="reports/venue-summary" element={<VenueBookingSummary />} />
            <Route path="payments" element={<Payments />} />
            <Route path="compliance" element={<Compliance />} />
            <Route path="strangers-meet" element={<StrangersMeet />} />
            <Route path="safety-checks" element={<SafetyChecks />} />
            <Route path="help-center" element={<HelpCenter />} />
            <Route path="community-guidelines" element={<CommunityGuidelines />} />
            <Route path="legal-terms" element={<LegalTerms />} />
            <Route path="chat-settings" element={<ChatSettings />} />
            <Route path="subscriptions" element={<SubscriptionManagement />} />
            <Route path="wallet" element={<WalletManagement />} />
            <Route path="cancellation-requests" element={<CancellationRequests />} />
            <Route path="cancelled-plans" element={<CancelledPartyPlans />} />
            <Route path="cancellation-analytics" element={<CancellationAnalytics />} />
            <Route path="booking-policies" element={<BookingPolicySettings />} />
            <Route path="refund-settings" element={<Navigate to="/booking-policies" replace />} />
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
