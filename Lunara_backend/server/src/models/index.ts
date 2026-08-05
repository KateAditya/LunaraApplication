import User, { UserRole } from './User';
import Venue from './Venue';
import Booking from './Booking';
import GroupBooking from './GroupBooking';
import Payment from './Payment';
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
import SafetyCheck from './SafetyCheck';
import DeletedAccount from './DeletedAccount';
import PlanTimeLock from './PlanTimeLock';
import PlanTimeLockConfig from './PlanTimeLockConfig';
import PlanTimeLockConfigHistory from './PlanTimeLockConfigHistory';
import NotificationJob from './NotificationJob';
import NightInterest from './NightInterest';
import NightPartnerRequest from './NightPartnerRequest';
import NightPartnerMatch from './NightPartnerMatch';
import Notification from './Notification';
import Ticket, { TicketStatus, StorageCleanupStatus } from './Ticket';
import PartySafetyCheck from './PartySafetyCheck';
import AuditLog from './AuditLog';
import WalletTransaction from './WalletTransaction';
import PartyReview from './PartyReview';
import ReliabilityHistory from './ReliabilityHistory';
import RewardPointLedger from './RewardPointLedger';

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

Venue.hasMany(GroupParty, { foreignKey: 'venueId', as: 'groupParties', onDelete: 'CASCADE' });
GroupParty.belongsTo(Venue, { foreignKey: 'venueId', as: 'venue' });

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
    PartyPlanRequest,
    PartyPlanCancellationRequest,
    UserPenalty,
    City,
    ChatSubscription,
    SubscriptionPackage,
    UserSubscription,
    SafetyCheck,
    DeletedAccount,
    PartySafetyCheck,
    AuditLog,
    WalletTransaction,
    PartyReview,
    ReliabilityHistory,
    RewardPointLedger,
};

// Export sync function
export const syncModels = async (options?: { force?: boolean; alter?: boolean }) => {
    try {
        // Sync in order of dependencies
        await User.sync(options);
        await Venue.sync(options);
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
        await PartyPlan.sync(options);
        await Ad.sync(options);
        await GroupParty.sync(options);
        await StrangersMeetRequest.sync(options);
        await StrangersMeetJoiner.sync(options);
        await PartyPlanRequest.sync(options);
        await PartyPlanCancellationRequest.sync(options);
        await UserPenalty.sync(options);
        await City.sync(options);
        await Area.sync(options);
        await ChatSubscription.sync(options);
        await SubscriptionPackage.sync(options);
        await UserSubscription.sync(options);
        await SafetyCheck.sync(options);
        await DeletedAccount.sync(options);
        await PlanTimeLock.sync(options);
        await PlanTimeLockConfig.sync(options);
        await PlanTimeLockConfigHistory.sync(options);
        await NotificationJob.sync(options);
        await NightInterest.sync(options);
        await NightPartnerRequest.sync(options);
        await NightPartnerMatch.sync(options);
        await PartySafetyCheck.sync(options);

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
    SafetyCheck,
    PlanTimeLock,
    PlanTimeLockConfig,
    PlanTimeLockConfigHistory,
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
    syncModels,
};
