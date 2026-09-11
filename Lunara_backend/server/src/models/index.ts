import sequelize from '../config/database';
import User, { UserRole } from './User';
import Venue from './Venue';
import Booking from './Booking';
import GroupBooking from './GroupBooking';
import Payment from './Payment';
import PaymentIntent from './PaymentIntent';
import BookingTablePackage from './BookingTablePackage';
import BookingMember from './BookingMember';
import Plan from './Plan';
import PlanJoinRequest from './PlanJoinRequest';
import Conversation from './Conversation';
import Message from './Message';
import PasswordResetToken from './PasswordResetToken';
import EmailVerification from './EmailVerification';
import OTPVerification from './OTPVerification';
import UserProfile from './UserProfile';
import UserPhoto from './UserPhoto';
import UserInterest from './UserInterest';
import UserPreference from './UserPreference';
import UserMatch from './UserMatch';
import SocialConnection from './SocialConnection';
import VenueImage from './VenueImage';
import VenueComplianceLog from './VenueComplianceLog';
import HelpArticle from './HelpArticle';
import CommunityGuideline from './CommunityGuideline';
import LegalDocument from './LegalDocument';
import PartyPlan from './PartyPlan';
import Ad from './Ad';
import GroupParty from './GroupParty';
import StrangersMeetRequest from './StrangersMeetRequest';
import StrangersMeetJoiner from './StrangersMeetJoiner';
import PartyPlanRequest from './PartyPlanRequest';
import PartyPlanCancellationRequest, { CancellationRequestStatus, CancellationReason } from './PartyPlanCancellationRequest';
import UserPenalty from './UserPenalty';
import City from './City';
import Area from './Area';
import ChatSubscription from './ChatSubscription';
import SubscriptionPackage from './SubscriptionPackage';
import UserSubscription from './UserSubscription';
import SubscriptionUsage from './SubscriptionUsage';
import SubscriptionFeature from './SubscriptionFeature';
import SubscriptionPlanFeature from './SubscriptionPlanFeature';
import SubscriptionTransaction from './SubscriptionTransaction';
import SubscriptionAddonPackage from './SubscriptionAddonPackage';
import UserAddon from './UserAddon';
import EntitlementAuditLog from './EntitlementAuditLog';
import UserEngagementEvent from './UserEngagementEvent';
import ProfileBoost from './ProfileBoost';
import SafetyCheck from './SafetyCheck';
import DeletedAccount from './DeletedAccount';
import PlanTimeLock from './PlanTimeLock';
import PlanTimeLockConfig from './PlanTimeLockConfig';
import PlanTimeLockConfigHistory from './PlanTimeLockConfigHistory';
import BookingPolicyConfig, { BookingPolicyType } from './BookingPolicyConfig';
import StrangersMeetCancellationRequest, { StrangersMeetCancellationStatus } from './StrangersMeetCancellationRequest';
import StrangersMeetHostCancellationRequest, { HostCancellationStatus, HostCancellationRefundMethod } from './StrangersMeetHostCancellationRequest';
import StrangersMeetMemberRefund, { MemberRefundStatus } from './StrangersMeetMemberRefund';
import LargePartyCancellationRequest, { LargePartyCancellationStatus, LargePartyRefundMethod } from './LargePartyCancellationRequest';
import NotificationJob from './NotificationJob';
import NightInterest from './NightInterest';
import NightPartnerRequest from './NightPartnerRequest';
import NightPartnerMatch from './NightPartnerMatch';
import Notification from './Notification';
import Ticket, { TicketStatus, StorageCleanupStatus } from './Ticket';
import PartySafetyCheck from './PartySafetyCheck';
import UserLike from './UserLike';
import AuditLog from './AuditLog';
import WalletTransaction from './WalletTransaction';
import PartyReview from './PartyReview';
import ReliabilityHistory from './ReliabilityHistory';
import RewardPointLedger from './RewardPointLedger';
import SmartWallet from './SmartWallet';
import SmartWalletConfig from './SmartWalletConfig';
import WalletPromotionalCampaign from './WalletPromotionalCampaign';
import WalletCashbackRule from './WalletCashbackRule';

// Smart Credit Wallet Associations
User.hasOne(SmartWallet, { foreignKey: 'userId', as: 'smartWallet' });
SmartWallet.belongsTo(User, { foreignKey: 'userId', as: 'user' });

User.hasMany(WalletTransaction, { foreignKey: 'userId', as: 'walletTransactions' });
WalletTransaction.belongsTo(User, { foreignKey: 'userId', as: 'user' });

SmartWallet.hasMany(WalletTransaction, { foreignKey: 'walletId', as: 'transactions' });
WalletTransaction.belongsTo(SmartWallet, { foreignKey: 'walletId', as: 'smartWallet' });

// ============================================================================
// Notification Associations
// ============================================================================

Notification.belongsTo(User, { foreignKey: 'recipientUserId', as: 'recipient' });
Notification.belongsTo(User, { foreignKey: 'actorUserId', as: 'actor' });

// ============================================================================
// Night Partner Associations
// ============================================================================

NightInterest.belongsTo(User, { foreignKey: 'userId', as: 'user' });
NightInterest.belongsTo(Venue, { foreignKey: 'venueId', as: 'venue' });

NightPartnerRequest.belongsTo(User, { foreignKey: 'hostId', as: 'host' });
NightPartnerRequest.belongsTo(User, { foreignKey: 'partnerId', as: 'partner' });
NightPartnerRequest.belongsTo(Venue, { foreignKey: 'venueId', as: 'venue' });
NightPartnerRequest.belongsTo(NightInterest, { foreignKey: 'nightInterestId', as: 'interest' });

NightPartnerMatch.belongsTo(User, { foreignKey: 'hostId', as: 'host' });
NightPartnerMatch.belongsTo(User, { foreignKey: 'partnerId', as: 'partner' });
NightPartnerMatch.belongsTo(Venue, { foreignKey: 'venueId', as: 'venue' });
NightPartnerMatch.belongsTo(NightPartnerRequest, { foreignKey: 'requestId', as: 'request' });
NightPartnerMatch.belongsTo(Booking, { foreignKey: 'bookingId', as: 'booking' });
NightPartnerMatch.belongsTo(Conversation, { foreignKey: 'conversationId', as: 'conversation' });

// ============================================================================
// User Associations
// ============================================================================

// User -> Venues (owner)
User.hasMany(Venue, {
    foreignKey: 'ownerId',
    as: 'venues',
});

// User -> Bookings
User.hasMany(Booking, {
    foreignKey: 'userId',
    as: 'bookings',
});

// User -> Payments
User.hasMany(Payment, {
    foreignKey: 'userId',
    as: 'payments',
});

// User -> Group Bookings (organizer)
User.hasMany(GroupBooking, {
    foreignKey: 'organizerId',
    as: 'organizedGroupBookings',
});

// User -> Profile (1:1)
User.hasOne(UserProfile, {
    foreignKey: 'userId',
    as: 'profile',
    onDelete: 'CASCADE',
});

// User -> Photos
User.hasMany(UserPhoto, {
    foreignKey: 'userId',
    as: 'photos',
});

// User -> Interests
User.hasMany(UserInterest, {
    foreignKey: 'userId',
    as: 'interests',
});

// User -> Preferences (1:1)
User.hasOne(UserPreference, {
    foreignKey: 'userId',
    as: 'preferences',
    onDelete: 'CASCADE',
});

// User -> Password Reset Tokens
User.hasMany(PasswordResetToken, {
    foreignKey: 'userId',
    as: 'passwordResetTokens',
});

// User -> Email Verifications
User.hasMany(EmailVerification, {
    foreignKey: 'userId',
    as: 'emailVerifications',
});

// User -> UserSubscription (1:1 per active package)
User.hasMany(UserSubscription, {
    foreignKey: 'userId',
    as: 'subscriptions',
});
UserSubscription.belongsTo(User, {
    foreignKey: 'userId',
    as: 'user',
});

// User -> SafetyCheck (submitted)
User.hasMany(PlanTimeLock, {
    foreignKey: 'userId',
    as: 'timeLocks',
});
PlanTimeLock.belongsTo(User, {
    foreignKey: 'userId',
    as: 'user',
});

User.hasMany(SafetyCheck, {
    foreignKey: 'userId',
    as: 'submittedSafetyChecks',
});
SafetyCheck.belongsTo(User, {
    foreignKey: 'userId',
    as: 'user',
});

// User -> SafetyCheck (about partner)
User.hasMany(SafetyCheck, {
    foreignKey: 'partnerId',
    as: 'receivedSafetyChecks',
});
SafetyCheck.belongsTo(User, {
    foreignKey: 'partnerId',
    as: 'partner',
});

SubscriptionPackage.hasMany(UserSubscription, {
    foreignKey: 'packageId',
    as: 'userSubscriptions',
});
UserSubscription.belongsTo(SubscriptionPackage, {
    foreignKey: 'packageId',
    as: 'package',
});

// User -> UserAddon (1:N)
User.hasMany(UserAddon, {
    foreignKey: 'userId',
    as: 'addons',
    onDelete: 'CASCADE',
});
UserAddon.belongsTo(User, {
    foreignKey: 'userId',
    as: 'user',
});

// SubscriptionAddonPackage -> UserAddon (1:N)
SubscriptionAddonPackage.hasMany(UserAddon, {
    foreignKey: 'addonPackageId',
    as: 'userAddons',
});
UserAddon.belongsTo(SubscriptionAddonPackage, {
    foreignKey: 'addonPackageId',
    as: 'addonPackage',
});

// User -> EntitlementAuditLog (1:N)
User.hasMany(EntitlementAuditLog, {
    foreignKey: 'userId',
    as: 'entitlementAuditLogs',
    onDelete: 'CASCADE',
});
EntitlementAuditLog.belongsTo(User, {
    foreignKey: 'userId',
    as: 'user',
});

// ============================================================================
// Venue Associations
// ============================================================================

Venue.belongsTo(User, {
    foreignKey: 'ownerId',
    as: 'owner',
});

Venue.hasMany(Booking, {
    foreignKey: 'venueId',
    as: 'bookings',
    onDelete: 'CASCADE',
});

Venue.hasMany(VenueImage, {
    foreignKey: 'venueId',
    as: 'images',
    onDelete: 'CASCADE',
});

// Venue -> Compliance Logs
Venue.hasMany(VenueComplianceLog, {
    foreignKey: 'venueId',
    as: 'complianceLogs',
    onDelete: 'CASCADE',
});

// Venue -> Ads
Venue.hasMany(Ad, {
    foreignKey: 'venueId',
    as: 'ads',
    onDelete: 'CASCADE',
});

Ad.belongsTo(Venue, {
    foreignKey: 'venueId',
    as: 'venue',
});

VenueComplianceLog.belongsTo(Venue, {
    foreignKey: 'venueId',
    as: 'venue',
});

// ============================================================================
// Booking Associations
// ============================================================================

Booking.belongsTo(User, {
    foreignKey: 'userId',
    as: 'customer',
});

Booking.belongsTo(User, {
    foreignKey: 'userId',
    as: 'user',
});

Booking.belongsTo(Venue, {
    foreignKey: 'venueId',
    as: 'venue',
});

// Booking -> Ad (Party Event)
Booking.belongsTo(Ad, {
    foreignKey: 'partyEventId',
    as: 'partyEvent',
});
Ad.hasMany(Booking, {
    foreignKey: 'partyEventId',
    as: 'bookings',
});

Booking.hasOne(GroupBooking, {
    foreignKey: 'bookingId',
    as: 'groupBooking',
});

Booking.hasMany(Payment, {
    foreignKey: 'bookingId',
    as: 'payments',
});



// Booking -> TablePackages
Venue.hasMany(BookingTablePackage, {
    foreignKey: 'venueId',
    as: 'tablePackages',
    onDelete: 'CASCADE',
});
BookingTablePackage.belongsTo(Venue, {
    foreignKey: 'venueId',
    as: 'venue',
});

// GroupBooking -> BookingMembers
GroupBooking.hasMany(BookingMember, {
    foreignKey: 'groupBookingId',
    as: 'members',
});
BookingMember.belongsTo(GroupBooking, {
    foreignKey: 'groupBookingId',
    as: 'groupBooking',
});

// ============================================================================
// Group Booking Associations
// ============================================================================

GroupBooking.belongsTo(Booking, {
    foreignKey: 'bookingId',
    as: 'booking',
});

GroupBooking.belongsTo(User, {
    foreignKey: 'organizerId',
    as: 'organizer',
});

// ============================================================================
// Payment Associations
// ============================================================================

Payment.belongsTo(Booking, {
    foreignKey: 'bookingId',
    as: 'booking',
});

Payment.belongsTo(User, {
    foreignKey: 'userId',
    as: 'payer',
});

Payment.belongsTo(User, {
    foreignKey: 'userId',
    as: 'user',
});


// ============================================================================
// User Profile Associations
// ============================================================================

UserProfile.belongsTo(User, {
    foreignKey: 'userId',
    as: 'user',
});

// ============================================================================
// User Photo Associations
// ============================================================================

UserPhoto.belongsTo(User, {
    foreignKey: 'userId',
    as: 'user',
});

// ============================================================================
// User Interest Associations
// ============================================================================

UserInterest.belongsTo(User, {
    foreignKey: 'userId',
    as: 'user',
});

// ============================================================================
// User Preference Associations
// ============================================================================

UserPreference.belongsTo(User, {
    foreignKey: 'userId',
    as: 'user',
});

// ============================================================================
// Password Reset Token Associations
// ============================================================================

PasswordResetToken.belongsTo(User, {
    foreignKey: 'userId',
    as: 'user',
});

// ============================================================================
// Email Verification Associations
// ============================================================================

EmailVerification.belongsTo(User, {
    foreignKey: 'userId',
    as: 'user',
});

// ============================================================================
// Social Connection Associations
// ============================================================================

SocialConnection.belongsTo(User, {
    foreignKey: 'requesterId',
    as: 'requester',
});

SocialConnection.belongsTo(User, {
    foreignKey: 'receiverId',
    as: 'receiver',
});

// ============================================================================
// User Match Associations
// ============================================================================

UserMatch.belongsTo(User, {
    foreignKey: 'user1Id',
    as: 'user1',
});

UserMatch.belongsTo(User, {
    foreignKey: 'user2Id',
    as: 'user2',
});

UserMatch.belongsTo(Venue, {
    foreignKey: 'venueId',
    as: 'suggestedVenue',
    onDelete: 'SET NULL',
});

// ============================================================================
// Venue Image Associations
// ============================================================================

VenueImage.belongsTo(Venue, {
    foreignKey: 'venueId',
    as: 'venue',
});

VenueImage.belongsTo(User, {
    foreignKey: 'uploadedBy',
    as: 'uploader',
});

// ============================================================================
// Plan Associations
// ============================================================================

User.hasMany(Plan, { foreignKey: 'userId', as: 'plans' });
Plan.belongsTo(User, { foreignKey: 'userId', as: 'host' });

Venue.hasMany(Plan, { foreignKey: 'venueId', as: 'plans', onDelete: 'CASCADE' });
Plan.belongsTo(Venue, { foreignKey: 'venueId', as: 'venue' });

// ============================================================================
// Party Plan Associations
// ============================================================================

User.hasMany(PartyPlan, { foreignKey: 'userId', as: 'partyPlans' });
PartyPlan.belongsTo(User, { foreignKey: 'userId', as: 'creator' });
PartyPlan.belongsTo(User, { foreignKey: 'userId', as: 'user' });

Venue.hasMany(PartyPlan, { foreignKey: 'venueId', as: 'partyPlans', onDelete: 'CASCADE' });
PartyPlan.belongsTo(Venue, { foreignKey: 'venueId', as: 'venue' });

PartyPlan.hasMany(PartyPlanRequest, { foreignKey: 'planId', as: 'requests', onDelete: 'CASCADE' });
PartyPlanRequest.belongsTo(PartyPlan, { foreignKey: 'planId', as: 'plan' });

PartyPlanRequest.belongsTo(User, { foreignKey: 'requesterId', as: 'requester' });
User.hasMany(PartyPlanRequest, { foreignKey: 'requesterId', as: 'partyPlanRequests' });

PartyPlan.hasMany(PartyPlanCancellationRequest, { foreignKey: 'planId', as: 'cancellationRequests', onDelete: 'CASCADE' });
PartyPlanCancellationRequest.belongsTo(PartyPlan, { foreignKey: 'planId', as: 'plan' });
PartyPlanCancellationRequest.belongsTo(Booking, { foreignKey: 'bookingId', as: 'booking' });
PartyPlanCancellationRequest.belongsTo(User, { foreignKey: 'requestedById', as: 'requester' });
PartyPlanCancellationRequest.belongsTo(User, { foreignKey: 'recipientUserId', as: 'recipient' });
User.hasMany(PartyPlanCancellationRequest, { foreignKey: 'requestedById', as: 'sentCancellationRequests' });
User.hasMany(PartyPlanCancellationRequest, { foreignKey: 'recipientUserId', as: 'receivedCancellationRequests' });

User.hasMany(UserPenalty, { foreignKey: 'userId', as: 'penalties', onDelete: 'CASCADE' });
UserPenalty.belongsTo(User, { foreignKey: 'userId', as: 'user' });

// ============================================================================
// Group Party Associations
// ============================================================================

User.hasMany(GroupParty, { foreignKey: 'userId', as: 'groupParties' });
GroupParty.belongsTo(User, { foreignKey: 'userId', as: 'creator' });
GroupParty.belongsTo(User, { foreignKey: 'userId', as: 'user' });

Venue.hasMany(GroupParty, { foreignKey: 'venueId', as: 'groupParties', onDelete: 'CASCADE' });
GroupParty.belongsTo(Venue, { foreignKey: 'venueId', as: 'venue' });

// ============================================================================
// Ticket Associations
// ============================================================================
User.hasMany(Ticket, { foreignKey: 'userId', as: 'tickets', onDelete: 'CASCADE' });
Ticket.belongsTo(User, { foreignKey: 'userId', as: 'user' });

Venue.hasMany(Ticket, { foreignKey: 'venueId', as: 'tickets', onDelete: 'CASCADE' });
Ticket.belongsTo(Venue, { foreignKey: 'venueId', as: 'venue' });

// ============================================================================
// Strangers Meet Request & Joiner Associations
// ============================================================================

User.hasMany(StrangersMeetRequest, { foreignKey: 'userId', as: 'strangersMeetRequests' });
StrangersMeetRequest.belongsTo(User, { foreignKey: 'userId', as: 'user' });

Venue.hasMany(StrangersMeetRequest, { foreignKey: 'venueId', as: 'strangersMeetRequests', onDelete: 'CASCADE' });
StrangersMeetRequest.belongsTo(Venue, { foreignKey: 'venueId', as: 'venue' });

StrangersMeetRequest.hasMany(StrangersMeetJoiner, { foreignKey: 'strangersMeetRequestId', as: 'joiners', onDelete: 'CASCADE' });
StrangersMeetJoiner.belongsTo(StrangersMeetRequest, { foreignKey: 'strangersMeetRequestId', as: 'strangersMeetRequest' });

User.hasMany(StrangersMeetJoiner, { foreignKey: 'userId', as: 'joinedStrangersMeets', onDelete: 'CASCADE' });
StrangersMeetJoiner.belongsTo(User, { foreignKey: 'userId', as: 'user' });

StrangersMeetRequest.hasMany(StrangersMeetCancellationRequest, { foreignKey: 'meetId', as: 'cancellationRequests', onDelete: 'CASCADE' });
StrangersMeetCancellationRequest.belongsTo(StrangersMeetRequest, { foreignKey: 'meetId', as: 'meet' });

StrangersMeetJoiner.hasOne(StrangersMeetCancellationRequest, { foreignKey: 'joinerId', as: 'cancellationRequest', onDelete: 'CASCADE' });
StrangersMeetCancellationRequest.belongsTo(StrangersMeetJoiner, { foreignKey: 'joinerId', as: 'joiner' });

User.hasMany(StrangersMeetCancellationRequest, { foreignKey: 'userId', as: 'sentMeetCancellationRequests', onDelete: 'CASCADE' });
StrangersMeetCancellationRequest.belongsTo(User, { foreignKey: 'userId', as: 'user' });

User.hasMany(StrangersMeetCancellationRequest, { foreignKey: 'hostUserId', as: 'receivedMeetCancellationRequests', onDelete: 'CASCADE' });
StrangersMeetCancellationRequest.belongsTo(User, { foreignKey: 'hostUserId', as: 'host' });

StrangersMeetRequest.hasMany(StrangersMeetHostCancellationRequest, { foreignKey: 'meetId', as: 'hostCancellationRequests', onDelete: 'CASCADE' });
StrangersMeetHostCancellationRequest.belongsTo(StrangersMeetRequest, { foreignKey: 'meetId', as: 'meet' });

User.hasMany(StrangersMeetHostCancellationRequest, { foreignKey: 'hostUserId', as: 'sentHostCancellationRequests', onDelete: 'CASCADE' });
StrangersMeetHostCancellationRequest.belongsTo(User, { foreignKey: 'hostUserId', as: 'host' });
StrangersMeetHostCancellationRequest.belongsTo(User, { foreignKey: 'adminReviewedBy', as: 'reviewer' });

StrangersMeetHostCancellationRequest.hasMany(StrangersMeetMemberRefund, { foreignKey: 'hostCancellationRequestId', as: 'memberRefunds', onDelete: 'CASCADE' });
StrangersMeetMemberRefund.belongsTo(StrangersMeetHostCancellationRequest, { foreignKey: 'hostCancellationRequestId', as: 'hostCancellationRequest' });

StrangersMeetRequest.hasMany(StrangersMeetMemberRefund, { foreignKey: 'meetId', as: 'memberRefunds', onDelete: 'CASCADE' });
StrangersMeetMemberRefund.belongsTo(StrangersMeetRequest, { foreignKey: 'meetId', as: 'meet' });

StrangersMeetJoiner.hasMany(StrangersMeetMemberRefund, { foreignKey: 'joinerId', as: 'refunds', onDelete: 'CASCADE' });
StrangersMeetMemberRefund.belongsTo(StrangersMeetJoiner, { foreignKey: 'joinerId', as: 'joiner' });

User.hasMany(StrangersMeetMemberRefund, { foreignKey: 'userId', as: 'strangerMeetRefunds', onDelete: 'CASCADE' });
StrangersMeetMemberRefund.belongsTo(User, { foreignKey: 'userId', as: 'user' });
StrangersMeetMemberRefund.belongsTo(User, { foreignKey: 'paidByAdminId', as: 'paidByAdmin' });

// Large Party Cancellation Associations
Booking.hasOne(LargePartyCancellationRequest, { foreignKey: 'bookingId', as: 'cancellationRequest', onDelete: 'CASCADE' });
LargePartyCancellationRequest.belongsTo(Booking, { foreignKey: 'bookingId', as: 'booking' });
User.hasMany(LargePartyCancellationRequest, { foreignKey: 'userId', as: 'largePartyCancellations', onDelete: 'CASCADE' });
LargePartyCancellationRequest.belongsTo(User, { foreignKey: 'userId', as: 'user' });
Venue.hasMany(LargePartyCancellationRequest, { foreignKey: 'venueId', as: 'largePartyCancellations', onDelete: 'SET NULL' });
LargePartyCancellationRequest.belongsTo(Venue, { foreignKey: 'venueId', as: 'venue' });
LargePartyCancellationRequest.belongsTo(User, { foreignKey: 'adminReviewedBy', as: 'adminReviewer' });
LargePartyCancellationRequest.belongsTo(User, { foreignKey: 'paidByAdminId', as: 'adminPayer' });

Plan.hasMany(PlanJoinRequest, { foreignKey: 'planId', as: 'joinRequests' });
PlanJoinRequest.belongsTo(Plan, { foreignKey: 'planId', as: 'plan' });

PlanJoinRequest.belongsTo(User, { foreignKey: 'requesterId', as: 'requester' });
User.hasMany(PlanJoinRequest, { foreignKey: 'requesterId', as: 'planJoinRequests' });

// ============================================================================
// Chat Associations
// ============================================================================

User.hasMany(Conversation, { foreignKey: 'participantOne', as: 'conversationsAsOne' });
User.hasMany(Conversation, { foreignKey: 'participantTwo', as: 'conversationsAsTwo' });
Conversation.belongsTo(User, { foreignKey: 'participantOne', as: 'userOne' });
Conversation.belongsTo(User, { foreignKey: 'participantTwo', as: 'userTwo' });

Conversation.hasMany(Message, { foreignKey: 'conversationId', as: 'messages' });
Message.belongsTo(Conversation, { foreignKey: 'conversationId', as: 'conversation' });

Message.belongsTo(User, { foreignKey: 'senderId', as: 'sender' });
User.hasMany(Message, { foreignKey: 'senderId', as: 'sentMessages' });

// ============================================================================
// ChatSubscription Associations
// ============================================================================

Conversation.hasMany(ChatSubscription, { foreignKey: 'conversationId', as: 'chatSubscriptions' });
ChatSubscription.belongsTo(Conversation, { foreignKey: 'conversationId', as: 'conversation' });
ChatSubscription.belongsTo(User, { foreignKey: 'paidById', as: 'paidBy' });

// ============================================================================
// Exports
// ============================================================================

// UserLike Associations
UserLike.belongsTo(User, { foreignKey: 'userId', as: 'user' });
UserLike.belongsTo(User, { foreignKey: 'targetUserId', as: 'targetUser' });
User.hasMany(UserLike, { foreignKey: 'userId', as: 'sentLikes' });
User.hasMany(UserLike, { foreignKey: 'targetUserId', as: 'receivedLikes' });

export {
    User,
    UserRole,
    Venue,
    Booking,
    GroupBooking,
    Payment,
    BookingTablePackage,
    BookingMember,
    Plan,
    PlanJoinRequest,
    Conversation,
    Message,
    PasswordResetToken,
    EmailVerification,
    OTPVerification,
    UserProfile,
    UserPhoto,
    UserInterest,
    UserPreference,
    UserMatch,
    SocialConnection,
    VenueImage,
    VenueComplianceLog,
    HelpArticle,
    CommunityGuideline,
    LegalDocument,
    PartyPlan,
    Ad,
    GroupParty,
    StrangersMeetRequest,
    StrangersMeetJoiner,
    StrangersMeetCancellationRequest,
    StrangersMeetCancellationStatus,
    StrangersMeetHostCancellationRequest,
    HostCancellationStatus,
    HostCancellationRefundMethod,
    StrangersMeetMemberRefund,
    MemberRefundStatus,
    PartyPlanRequest,
    PartyPlanCancellationRequest,
    UserPenalty,
    City,
    ChatSubscription,
    SubscriptionPackage,
    UserSubscription,
    SubscriptionUsage,
    SubscriptionFeature,
    SubscriptionPlanFeature,
    SubscriptionTransaction,
    SubscriptionAddonPackage,
    UserAddon,
    EntitlementAuditLog,
    SafetyCheck,
    DeletedAccount,
    PartySafetyCheck,
    AuditLog,
    WalletTransaction,
    PartyReview,
    ReliabilityHistory,
    RewardPointLedger,
    Ticket,
    TicketStatus,
    Area,
    SmartWallet,
    SmartWalletConfig,
    WalletPromotionalCampaign,
    WalletCashbackRule,
    UserLike,
    UserEngagementEvent,
    ProfileBoost,
    PlanTimeLock,
    PlanTimeLockConfig,
    PlanTimeLockConfigHistory,
    NotificationJob,
    NightInterest,
    NightPartnerRequest,
    NightPartnerMatch,
    Notification,
    LargePartyCancellationRequest,
    LargePartyCancellationStatus,
    LargePartyRefundMethod,
};

// Export sync function
export const syncModels = async (options?: { force?: boolean; alter?: boolean }) => {
    try {
        // Safe individual startup schema migrations executed BEFORE model syncs
        const safeQueries = [
            `CREATE TABLE IF NOT EXISTS profile_boosts (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                started_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
                status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
                duration_minutes INTEGER NOT NULL DEFAULT 30,
                transaction_id UUID,
                metadata JSONB,
                created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
            );`,
            `CREATE TABLE IF NOT EXISTS payment_intents (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                payment_reference VARCHAR(100) NOT NULL UNIQUE,
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                entity_type VARCHAR(50) NOT NULL,
                entity_id VARCHAR(100) NOT NULL,
                amount NUMERIC(10,2) NOT NULL,
                wallet_amount_used NUMERIC(10,2) DEFAULT 0,
                razorpay_amount NUMERIC(10,2) DEFAULT 0,
                currency VARCHAR(3) DEFAULT 'INR',
                status VARCHAR(30) DEFAULT 'initiated',
                payment_method VARCHAR(30) DEFAULT 'razorpay',
                razorpay_order_id VARCHAR(100),
                razorpay_payment_id VARCHAR(100),
                razorpay_signature VARCHAR(255),
                expires_at TIMESTAMP WITH TIME ZONE,
                failure_reason TEXT,
                metadata JSONB,
                created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
            );`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_first_check_status VARCHAR(30) DEFAULT 'pending';`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_first_check_responded_at TIMESTAMP WITH TIME ZONE;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_final_check_status VARCHAR(30) DEFAULT 'pending';`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_final_check_responded_at TIMESTAMP WITH TIME ZONE;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reach_verification_stage VARCHAR(30) DEFAULT 'pre_event_check';`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS attendance_decision VARCHAR(40) DEFAULT 'pending';`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reach_refund_decision VARCHAR(40) DEFAULT 'pending';`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS verification_expiry_at TIMESTAMP WITH TIME ZONE;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_arrival_confirmed BOOLEAN DEFAULT false;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_arrival_time TIMESTAMP WITH TIME ZONE;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_lat_lang_check_in VARCHAR(255);`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS expired_no_show_cancelled BOOLEAN DEFAULT false;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_24h_sent BOOLEAN DEFAULT false;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_3h_sent BOOLEAN DEFAULT false;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_1h_sent BOOLEAN DEFAULT false;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_30m_sent BOOLEAN DEFAULT false;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_2h_sent BOOLEAN DEFAULT false;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_20m_sent BOOLEAN DEFAULT false;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_10m_sent BOOLEAN DEFAULT false;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_5m_sent BOOLEAN DEFAULT false;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_on_time_sent BOOLEAN DEFAULT false;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_post_5m_sent BOOLEAN DEFAULT false;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_post_10m_sent BOOLEAN DEFAULT false;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_post_30m_sent BOOLEAN DEFAULT false;`,

            `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS guest_arrival_confirmed BOOLEAN DEFAULT false;`,
            `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS guest_arrival_time TIMESTAMP WITH TIME ZONE;`,
            `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS guest_first_check_status VARCHAR(30) DEFAULT 'pending';`,
            `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS guest_first_check_responded_at TIMESTAMP WITH TIME ZONE;`,
            `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS guest_final_check_status VARCHAR(30) DEFAULT 'pending';`,
            `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS guest_final_check_responded_at TIMESTAMP WITH TIME ZONE;`,
            `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS lat_lang_check_in VARCHAR(255);`,
            `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS payment_timeout_at TIMESTAMP WITH TIME ZONE;`,
            `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS joiner_payment_status VARCHAR(50) DEFAULT 'unpaid';`,
            `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS joiner_razorpay_order_id VARCHAR(255);`,
            `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS joiner_razorpay_payment_id VARCHAR(255);`,
            `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMP WITH TIME ZONE;`,
            `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS cancelled_by UUID;`,
            `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS cancellation_reason VARCHAR(100);`,
            `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS previous_status VARCHAR(50);`,
            `ALTER TABLE party_plan_requests ADD COLUMN IF NOT EXISTS request_type VARCHAR(50) DEFAULT 'public_request';`,

            `ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS expiration_alert_sent BOOLEAN DEFAULT false;`,
            `ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS reminder1_day_sent BOOLEAN DEFAULT false;`,
            `ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS reminder8_hour_sent BOOLEAN DEFAULT false;`,
            `ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS reminder5_hour_sent BOOLEAN DEFAULT false;`,
            `ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS reminder2_hour_sent BOOLEAN DEFAULT false;`,
            `ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS reminder1_hour_sent BOOLEAN DEFAULT false;`,
            `ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS expiry_notified BOOLEAN DEFAULT false;`,
            `ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS last_notified_at TIMESTAMP WITH TIME ZONE;`,

            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS bank_name VARCHAR(255);`,
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS account_number VARCHAR(255);`,
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS account_holder_name VARCHAR(255);`,
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS ifsc_code VARCHAR(255);`,
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS upi_id VARCHAR(255);`,
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS upi_number VARCHAR(255);`,
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS platform_charge_per_seat NUMERIC;`,
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS settlement_transaction_id VARCHAR(255);`,
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS settlement_amount NUMERIC;`,
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS settlement_date TIMESTAMP WITH TIME ZONE;`,
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS settlement_method VARCHAR(255);`,
            // Strangers Meet: escalation / lifecycle / preference columns added after initial migration
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS food_preference VARCHAR(100);`,
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS drink_preference VARCHAR(100);`,
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS escalated_at TIMESTAMP WITH TIME ZONE;`,
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS escalation_reason TEXT;`,
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS admin_resolution VARCHAR(100);`,
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS admin_resolution_notes TEXT;`,
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS admin_resolved_at TIMESTAMP WITH TIME ZONE;`,
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS admin_resolved_by UUID;`,
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS host_not_started_at TIMESTAMP WITH TIME ZONE;`,
            `ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS host_not_started_reason TEXT;`,
            // Party Plans: venue-reach confirmation + lifecycle timestamp columns added after initial migration
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reach_confirmation_30m_sent BOOLEAN DEFAULT false;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_reach_status VARCHAR(30) DEFAULT 'PENDING';`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_reach_confirmed_at TIMESTAMP WITH TIME ZONE;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_reach_confirmation_source VARCHAR(50);`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS host_reach_notification_id VARCHAR(100);`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMP WITH TIME ZONE;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS payment_deadline_at TIMESTAMP WITH TIME ZONE;`,
            `ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS matched_request_id UUID;`,
            // Night Partner Requests: payment columns added after initial migration
            `ALTER TABLE night_partner_requests ADD COLUMN IF NOT EXISTS host_paid BOOLEAN DEFAULT false;`,
            `ALTER TABLE night_partner_requests ADD COLUMN IF NOT EXISTS host_amount DECIMAL(10,2);`,
            `ALTER TABLE night_partner_requests ADD COLUMN IF NOT EXISTS razorpay_order_id VARCHAR(255);`,
        ];

        for (const q of safeQueries) {
            try {
                await sequelize.query(q);
            } catch (qErr: any) {
                console.warn('⚠️ Startup migration note:', qErr?.message);
            }
        }
        await sequelize.query(`ALTER TYPE enum_group_parties_status ADD VALUE IF NOT EXISTS 'completed';`).catch(() => {});

        // Sync in order of dependencies
        await User.sync(options);
        await Venue.sync(options);
        try {
            await sequelize.query(`
                ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reminder_2h_sent BOOLEAN DEFAULT FALSE;
                ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reminder_1h_sent BOOLEAN DEFAULT FALSE;
                ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reminder_30m_sent BOOLEAN DEFAULT FALSE;
            `);
        } catch (colErr) {
            console.warn('⚠️ Auto-adding Booking reminder columns note:', colErr);
        }

        await Booking.sync(options);
        await GroupBooking.sync(options);
        await Payment.sync(options);
        await BookingTablePackage.sync(options);
        await BookingMember.sync(options);
        await Plan.sync(options);
        await PlanJoinRequest.sync(options);
        await Conversation.sync(options);
        await Message.sync(options);
        await PasswordResetToken.sync(options);
        await EmailVerification.sync(options);
        await OTPVerification.sync(options);
        await UserProfile.sync(options);
        await UserPhoto.sync(options);
        await UserInterest.sync(options);
        await UserPreference.sync(options);
        await UserMatch.sync(options);
        await SocialConnection.sync(options);
        await VenueImage.sync(options);
        await VenueComplianceLog.sync(options);
        await HelpArticle.sync(options);
        await CommunityGuideline.sync(options);
        await LegalDocument.sync(options);
        try {
            await sequelize.query(`
                ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_24h_sent BOOLEAN DEFAULT FALSE;
                ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_3h_sent BOOLEAN DEFAULT FALSE;
                ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_1h_sent BOOLEAN DEFAULT FALSE;
                ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_30m_sent BOOLEAN DEFAULT FALSE;
                ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_2h_sent BOOLEAN DEFAULT FALSE;
                ALTER TABLE party_plans ADD COLUMN IF NOT EXISTS reminder_10m_sent BOOLEAN DEFAULT FALSE;
            `);
        } catch (colErr) {
            console.warn('⚠️ Auto-adding PartyPlan reminder columns note:', colErr);
        }

        await PartyPlan.sync(options);
        await Ad.sync(options);
        try {
            await sequelize.query(`
                ALTER TABLE group_parties ADD COLUMN IF NOT EXISTS start_time VARCHAR(5);
                ALTER TABLE group_parties ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP WITH TIME ZONE;
                ALTER TABLE group_parties ADD COLUMN IF NOT EXISTS optional_mobile_number VARCHAR(255);
                ALTER TABLE group_parties ADD COLUMN IF NOT EXISTS food_preference VARCHAR(100);
                ALTER TABLE group_parties ADD COLUMN IF NOT EXISTS drink_preference VARCHAR(100);
                ALTER TABLE group_parties ADD COLUMN IF NOT EXISTS ticket_url VARCHAR(500);
                ALTER TABLE group_parties ADD COLUMN IF NOT EXISTS ticket_code VARCHAR(100);
                ALTER TABLE group_parties ADD COLUMN IF NOT EXISTS reminder_2h_sent BOOLEAN DEFAULT FALSE;
                ALTER TABLE group_parties ADD COLUMN IF NOT EXISTS reminder_1h_sent BOOLEAN DEFAULT FALSE;
                ALTER TABLE group_parties ADD COLUMN IF NOT EXISTS reminder_30m_sent BOOLEAN DEFAULT FALSE;
            `);
        } catch (colErr) {
            console.warn('⚠️ Auto-adding GroupParty reminder columns note:', colErr);
        }

        await GroupParty.sync(options);
        try {
            await sequelize.query(`
                ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS reminder_2h_sent BOOLEAN DEFAULT FALSE;
                ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS reminder_1h_sent BOOLEAN DEFAULT FALSE;
                ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS reminder_30m_sent BOOLEAN DEFAULT FALSE;
                ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS started_at TIMESTAMP WITH TIME ZONE;
                ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS started_by UUID;
                ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS duration_hours DECIMAL(4,2) DEFAULT 3.0;
                ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS expected_end_at TIMESTAMP WITH TIME ZONE;
                ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS ended_at TIMESTAMP WITH TIME ZONE;
                ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS ended_confirmed_by UUID;
                ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS ended_confirmed_at TIMESTAMP WITH TIME ZONE;
                ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS admin_confirmed_ended_at TIMESTAMP WITH TIME ZONE;
                ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS admin_confirmed_by UUID;
                ALTER TABLE strangers_meet_requests ADD COLUMN IF NOT EXISTS settlement_overdue BOOLEAN DEFAULT FALSE;
            `);
        } catch (colErr) {
            console.warn('⚠️ Auto-adding StrangersMeetRequest reminder columns note:', colErr);
        }
        try {
            await sequelize.query(`
                CREATE TABLE IF NOT EXISTS profile_boosts (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    started_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
                    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
                    duration_minutes INTEGER NOT NULL DEFAULT 30,
                    transaction_id UUID,
                    metadata JSONB,
                    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
                );

                ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS expiration_alert_sent BOOLEAN DEFAULT false;
                ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS reminder1_day_sent BOOLEAN DEFAULT false;
                ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS reminder8_hour_sent BOOLEAN DEFAULT false;
                ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS reminder5_hour_sent BOOLEAN DEFAULT false;
                ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS reminder2_hour_sent BOOLEAN DEFAULT false;
                ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS reminder1_hour_sent BOOLEAN DEFAULT false;
                ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS expiry_notified BOOLEAN DEFAULT false;
                ALTER TABLE "UserSubscriptions" ADD COLUMN IF NOT EXISTS last_notified_at TIMESTAMP WITH TIME ZONE;

                CREATE TABLE IF NOT EXISTS strangers_meet_cancellation_requests (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    meet_id UUID NOT NULL REFERENCES strangers_meet_requests(id) ON DELETE CASCADE,
                    joiner_id UUID NOT NULL REFERENCES strangers_meet_joiners(id) ON DELETE CASCADE,
                    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    host_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    status VARCHAR(30) NOT NULL DEFAULT 'pending',
                    reason VARCHAR(255) NOT NULL,
                    other_reason_text TEXT,
                    paid_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                    refund_amount DECIMAL(10,2),
                    wallet_transaction_id UUID,
                    reject_reason VARCHAR(255),
                    responded_at TIMESTAMP WITH TIME ZONE,
                    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
                );

                CREATE TABLE IF NOT EXISTS strangers_meet_host_cancellation_requests (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    meet_id UUID NOT NULL REFERENCES strangers_meet_requests(id) ON DELETE CASCADE,
                    host_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    reason VARCHAR(255) NOT NULL,
                    reason_text TEXT,
                    status VARCHAR(50) NOT NULL DEFAULT 'PENDING_ADMIN_REVIEW',
                    refund_policy_percentage DECIMAL(5,2),
                    refund_method VARCHAR(30),
                    total_collected_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                    total_refund_amount DECIMAL(10,2),
                    total_members_count INTEGER NOT NULL DEFAULT 0,
                    admin_reviewed_by UUID REFERENCES users(id),
                    admin_reviewed_at TIMESTAMP WITH TIME ZONE,
                    admin_notes TEXT,
                    host_deposit_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                    host_refund_type VARCHAR(30),
                    host_refund_percentage DECIMAL(5,2),
                    host_refund_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                    host_refund_destination VARCHAR(30),
                    host_refund_status VARCHAR(50) DEFAULT 'NONE',
                    host_payout_details JSONB,
                    host_settlement_transaction_id VARCHAR(100),
                    host_settled_at TIMESTAMP WITH TIME ZONE,
                    host_settled_by UUID,
                    host_settlement_notes TEXT,
                    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
                );

                CREATE TABLE IF NOT EXISTS strangers_meet_member_refunds (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    host_cancellation_request_id UUID NOT NULL REFERENCES strangers_meet_host_cancellation_requests(id) ON DELETE CASCADE,
                    meet_id UUID NOT NULL REFERENCES strangers_meet_requests(id) ON DELETE CASCADE,
                    joiner_id UUID NOT NULL REFERENCES strangers_meet_joiners(id) ON DELETE CASCADE,
                    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    paid_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                    refund_percentage DECIMAL(5,2) NOT NULL DEFAULT 100.00,
                    refund_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                    refund_method VARCHAR(30) NOT NULL DEFAULT 'WALLET',
                    status VARCHAR(50) NOT NULL DEFAULT 'PENDING',
                    wallet_transaction_id VARCHAR(100),
                    payment_reference VARCHAR(100),
                    payout_details JSONB,
                    paid_by_admin_id UUID REFERENCES users(id),
                    paid_at TIMESTAMP WITH TIME ZONE,
                    notes TEXT,
                    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
                );
            `);
        } catch (colErr: any) {
            console.warn('⚠️ Auto-migration tables warning:', colErr.message);
        }

        const modelsToSync = [
            StrangersMeetRequest,
            StrangersMeetJoiner,
            PartyPlanRequest,
            PartyPlanCancellationRequest,
            UserPenalty,
            City,
            Area,
            ChatSubscription,
            SubscriptionPackage,
            UserSubscription,
            SafetyCheck,
            DeletedAccount,
            PlanTimeLock,
            PlanTimeLockConfig,
            PlanTimeLockConfigHistory,
            NotificationJob,
            NightInterest,
            NightPartnerRequest,
            NightPartnerMatch,
            PartySafetyCheck,
            UserLike,
            UserEngagementEvent,
            ProfileBoost,
            Notification,
            WalletTransaction,
            PaymentIntent,
            Ticket,
            PartyReview,
            ReliabilityHistory,
            RewardPointLedger,
            SmartWallet,
            SmartWalletConfig,
            WalletPromotionalCampaign,
            AuditLog,
            SubscriptionUsage,
            SubscriptionFeature,
            SubscriptionPlanFeature,
            SubscriptionTransaction,
            SubscriptionAddonPackage,
            UserAddon,
            EntitlementAuditLog,
            BookingPolicyConfig,
            StrangersMeetCancellationRequest,
            StrangersMeetHostCancellationRequest,
            StrangersMeetMemberRefund,
            LargePartyCancellationRequest,
            WalletCashbackRule,  // was missing — wallet_cashback_rules table was never created
        ];
        for (const m of modelsToSync) {
            try {
                await m.sync(options);
            } catch (mErr: any) {
                console.warn(`Sync warning for ${m.name}: ${mErr?.message}`);
            }
        }
        try {
            await sequelize.query(`
                ALTER TABLE night_partner_requests ADD COLUMN IF NOT EXISTS payment_mode VARCHAR(20) DEFAULT 'SELF_PAY';
                ALTER TABLE night_partner_requests ADD COLUMN IF NOT EXISTS reminder_2h_sent BOOLEAN DEFAULT FALSE;
                ALTER TABLE night_partner_requests ADD COLUMN IF NOT EXISTS reminder_1h_sent BOOLEAN DEFAULT FALSE;
                ALTER TABLE night_partner_requests ADD COLUMN IF NOT EXISTS reminder_30m_sent BOOLEAN DEFAULT FALSE;
                ALTER TABLE night_partner_matches ADD COLUMN IF NOT EXISTS payment_mode VARCHAR(20) DEFAULT 'SELF_PAY';
                ALTER TABLE night_partner_matches ADD COLUMN IF NOT EXISTS cancellation_status VARCHAR(50) DEFAULT 'NONE';
                ALTER TABLE night_partner_matches ADD COLUMN IF NOT EXISTS cancellation_reason TEXT;
                ALTER TABLE night_partner_matches ADD COLUMN IF NOT EXISTS cancelled_by UUID;
                ALTER TABLE night_partner_matches ADD COLUMN IF NOT EXISTS reminder_2h_sent BOOLEAN DEFAULT FALSE;
                ALTER TABLE night_partner_matches ADD COLUMN IF NOT EXISTS reminder_1h_sent BOOLEAN DEFAULT FALSE;
                ALTER TABLE night_partner_matches ADD COLUMN IF NOT EXISTS reminder_30m_sent BOOLEAN DEFAULT FALSE;
            `);
        } catch (colErr) {
            console.warn('⚠️ Auto-adding NightPartner reminder columns note:', colErr);
        }

        // ── High-Speed Database Indexing for Rapid Querying ───────────────────────
        try {
            const performanceIndexes = [
                // Party Plans & Feed
                `CREATE INDEX IF NOT EXISTS idx_party_plans_status_date ON party_plans (status, plan_date_time);`,
                `CREATE INDEX IF NOT EXISTS idx_party_plans_status_created ON party_plans (status, created_at DESC);`,
                `CREATE INDEX IF NOT EXISTS idx_party_plans_user_status ON party_plans (user_id, status);`,
                `CREATE INDEX IF NOT EXISTS idx_party_plans_venue_status ON party_plans (venue_id, status);`,

                // Party Plan Requests
                `CREATE INDEX IF NOT EXISTS idx_party_plan_reqs_plan_status ON party_plan_requests (plan_id, status);`,
                `CREATE INDEX IF NOT EXISTS idx_party_plan_reqs_requester_status ON party_plan_requests (requester_id, status);`,
                `CREATE INDEX IF NOT EXISTS idx_party_plan_reqs_plan_user ON party_plan_requests (plan_id, requester_id);`,
                `CREATE INDEX IF NOT EXISTS idx_party_plan_reqs_status_timeout ON party_plan_requests (status, payment_timeout_at);`,

                // Bookings
                `CREATE INDEX IF NOT EXISTS idx_bookings_user_status ON bookings (user_id, status);`,
                `CREATE INDEX IF NOT EXISTS idx_bookings_venue_date ON bookings (venue_id, booking_date);`,
                `CREATE INDEX IF NOT EXISTS idx_bookings_large_party_status ON bookings (is_large_party_request, admin_approval_status);`,
                `CREATE INDEX IF NOT EXISTS idx_bookings_user_created ON bookings (user_id, created_at DESC);`,

                // Tickets
                `CREATE INDEX IF NOT EXISTS idx_tickets_user_status ON tickets (user_id, ticket_status);`,
                `CREATE INDEX IF NOT EXISTS idx_tickets_user_created ON tickets (user_id, created_at DESC);`,
                `CREATE INDEX IF NOT EXISTS idx_tickets_cleanup_status_del ON tickets (storage_cleanup_status, storage_deletion_at);`,

                // Notifications & Notification Jobs
                `CREATE INDEX IF NOT EXISTS idx_notifications_recipient_read ON notifications (recipient_user_id, is_read);`,
                `CREATE INDEX IF NOT EXISTS idx_notifications_recipient_created ON notifications (recipient_user_id, created_at DESC);`,
                `CREATE INDEX IF NOT EXISTS idx_notification_jobs_status_send_at ON notification_jobs (status, send_at);`,

                // User Subscriptions & Boosts
                `CREATE INDEX IF NOT EXISTS idx_user_subscriptions_status_end_date ON "UserSubscriptions" (status, end_date);`,
                `CREATE INDEX IF NOT EXISTS idx_profile_boosts_status_expires_at ON profile_boosts (status, expires_at);`,

                // Venues
                `CREATE INDEX IF NOT EXISTS idx_venues_city_active_status ON venues (city, is_active, status);`,
                `CREATE INDEX IF NOT EXISTS idx_venues_is_active_status ON venues (is_active, status);`,

                // Ads
                `CREATE INDEX IF NOT EXISTS idx_ads_active_dates ON ads (is_active, from_date, to_date);`,
                `CREATE INDEX IF NOT EXISTS idx_ads_city_active ON ads (city, is_active);`,

                // Strangers Meet Requests & Host Cancellations
                `CREATE INDEX IF NOT EXISTS idx_strangers_meet_user_status ON strangers_meet_requests (user_id, status);`,
                `CREATE INDEX IF NOT EXISTS idx_strangers_meet_venue_status ON strangers_meet_requests (venue_id, status);`,
                `CREATE INDEX IF NOT EXISTS idx_strangers_meet_event_dt ON strangers_meet_requests (event_date_time DESC);`,
                `CREATE INDEX IF NOT EXISTS idx_strangers_meet_status_pay_event ON strangers_meet_requests (status, payment_status, event_date_time);`,
                `CREATE INDEX IF NOT EXISTS idx_strangers_meet_status_expected_end ON strangers_meet_requests (status, expected_end_at);`,
                `CREATE INDEX IF NOT EXISTS idx_strangers_meet_status_started ON strangers_meet_requests (status, started_at);`,
                `CREATE INDEX IF NOT EXISTS idx_strangers_cancellations_status_created ON strangers_meet_host_cancellation_requests (status, created_at);`,

                // Smart Wallets & Transactions
                `CREATE INDEX IF NOT EXISTS idx_smart_wallets_user_id ON smart_wallets (user_id);`,
                `CREATE INDEX IF NOT EXISTS idx_wallet_tx_user_created ON wallet_transactions (user_id, created_at DESC);`,

                // Chat Messages & Conversations
                `CREATE INDEX IF NOT EXISTS idx_messages_conv_created ON messages (conversation_id, created_at ASC);`,
                `CREATE INDEX IF NOT EXISTS idx_conversations_user1_user2 ON conversations (user1_id, user2_id);`,

                // User Profiles
                `CREATE INDEX IF NOT EXISTS idx_user_profiles_user_id ON user_profiles (user_id);`,
                `CREATE INDEX IF NOT EXISTS idx_user_profiles_city ON user_profiles (city);`,
            ];

            for (const idxQuery of performanceIndexes) {
                try {
                    await sequelize.query(idxQuery);
                } catch (idxErr: any) {
                    // Non-fatal: table or column may not exist in specific environments
                }
            }
            console.log('⚡ High-performance database indexes applied successfully');
        } catch (indexErr) {
            console.warn('⚠️ Performance indexing note:', indexErr);
        }

        console.log('✅ All models synchronized successfully');
    } catch (error) {
        console.error('❌ Error synchronizing models:', error);
        throw error;
    }
};

export default {
    User,
    Venue,
    Booking,
    GroupBooking,
    Payment,
    BookingTablePackage,
    BookingMember,
    Plan,
    PlanJoinRequest,
    Conversation,
    Message,
    PasswordResetToken,
    EmailVerification,
    OTPVerification,
    UserProfile,
    UserPhoto,
    UserInterest,
    UserPreference,
    UserMatch,
    SocialConnection,
    VenueImage,
    VenueComplianceLog,
    HelpArticle,
    CommunityGuideline,
    LegalDocument,
    PartyPlan,
    Ad,
    GroupParty,
    StrangersMeetRequest,
    StrangersMeetJoiner,
    PartyPlanRequest,
    UserPenalty,
    City,
    Area,
    ChatSubscription,
    SubscriptionPackage,
    UserSubscription,
    SubscriptionAddonPackage,
    UserAddon,
    EntitlementAuditLog,
    SafetyCheck,
    PlanTimeLock,
    PlanTimeLockConfig,
    PlanTimeLockConfigHistory,
    BookingPolicyConfig,
    BookingPolicyType,
    NotificationJob,
    NightInterest,
    NightPartnerRequest,
    NightPartnerMatch,
    Notification,
    Ticket,
    TicketStatus,
    StorageCleanupStatus,
    PartySafetyCheck,
    PartyPlanCancellationRequest,
    CancellationRequestStatus,
    CancellationReason,
    SmartWallet,
    SmartWalletConfig,
    WalletPromotionalCampaign,
    WalletCashbackRule,
    UserLike,
    UserEngagementEvent,
    ProfileBoost,
    WalletTransaction,
    AuditLog,
    LargePartyCancellationRequest,
    LargePartyCancellationStatus,
    LargePartyRefundMethod,
    syncModels,
};
