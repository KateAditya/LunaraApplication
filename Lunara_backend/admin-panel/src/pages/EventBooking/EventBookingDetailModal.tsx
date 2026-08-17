import { Modal, Button, Row, Col, Badge } from 'react-bootstrap';
import { format } from 'date-fns';
import { useThemeMode } from '../../context/ThemeContext';

interface EventBookingDetailModalProps {
  show: boolean;
  onHide: () => void;
  booking: any;
  event: any;
}

export function EventBookingDetailModal({ show, onHide, booking, event }: EventBookingDetailModalProps) {
  const { mode } = useThemeMode();

  const isDark = mode === 'dark';
  const modalClass = isDark ? 'bg-dark text-white' : '';
  const headerClass = isDark ? 'border-secondary' : '';
  const textClass = isDark ? 'text-light' : 'text-dark';

  return (
    <Modal show={show} onHide={onHide} size="lg" centered contentClassName={modalClass}>
      <Modal.Header closeButton closeVariant={isDark ? 'white' : undefined} className={headerClass}>
        <Modal.Title>Booking Details: {booking?.bookingNumber}</Modal.Title>
      </Modal.Header>
      <Modal.Body>
        {booking && (
          <Row className="g-4">
            <Col md={6}>
              <h5 className={textClass}>Event Details</h5>
              <div className="mb-2"><strong>Name:</strong> {event?.title}</div>
              <div className="mb-2"><strong>Event Date:</strong> {event?.eventDate ? format(new Date(event.eventDate), 'dd-MM-yyyy') : 'N/A'}</div>
              <div className="mb-2"><strong>Venue:</strong> {event?.venue?.name || 'N/A'}</div>
              <div className="mb-2"><strong>Location:</strong> {event?.area}, {event?.city}</div>
              <div className="mb-2"><strong>Entry Price:</strong> ₹{event?.entryPrice || 0}</div>
            </Col>

            <Col md={6}>
              <h5 className={textClass}>User Details</h5>
              <div className="mb-2"><strong>Name:</strong> {booking.user?.firstName} {booking.user?.lastName}</div>
              <div className="mb-2"><strong>Mobile:</strong> {booking.user?.mobile || 'N/A'}</div>
              <div className="mb-2"><strong>Email:</strong> {booking.user?.email || 'N/A'}</div>
            </Col>

            <Col md={6}>
              <h5 className={textClass}>Booking Summary</h5>
              <div className="mb-2"><strong>Booking Date:</strong> {format(new Date(booking.createdAt), 'dd-MM-yyyy HH:mm')}</div>
              <div className="mb-2"><strong>Quantity:</strong> {booking.numberOfGuests} Entries</div>
              <div className="mb-2"><strong>Total Amount:</strong> ₹{booking.totalAmount}</div>
              <div className="mb-2">
                <strong>Booking Status:</strong>{' '}
                <Badge bg={booking.status === 'confirmed' ? 'success' : booking.status === 'cancelled' ? 'danger' : 'warning'}>
                  {booking.status.toUpperCase()}
                </Badge>
              </div>
            </Col>

            <Col md={6}>
              <h5 className={textClass}>Payment Information</h5>
              <div className="mb-2">
                <strong>Payment Status:</strong>{' '}
                {Number(booking.totalAmount) === 0 ? (
                  <Badge bg="success">FREE</Badge>
                ) : (
                  <Badge bg={booking.paymentStatus === 'paid' ? 'success' : booking.paymentStatus === 'failed' ? 'danger' : 'warning'}>
                    {booking.paymentStatus.toUpperCase()}
                  </Badge>
                )}
              </div>
              {booking.razorpayOrderId && (
                <div className="mb-2"><strong>Razorpay Order ID:</strong> {booking.razorpayOrderId}</div>
              )}
            </Col>

            {booking.ticket && (
              <Col md={12}>
                <hr className={headerClass} />
                <h5 className={textClass}>Ticket Information</h5>
                <div className="mb-2"><strong>Ticket Number:</strong> {booking.ticket.ticketNumber}</div>
                <div className="mb-2">
                  <strong>Ticket Status:</strong>{' '}
                  <Badge bg={booking.ticket.status === 'valid' ? 'success' : 'secondary'}>
                    {booking.ticket.status.toUpperCase()}
                  </Badge>
                </div>
              </Col>
            )}
          </Row>
        )}
      </Modal.Body>
      <Modal.Footer className={headerClass}>
        <Button variant="secondary" onClick={onHide}>
          Close
        </Button>
      </Modal.Footer>
    </Modal>
  );
}
