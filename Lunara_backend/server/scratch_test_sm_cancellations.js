require('./dist/models');
const { StrangersMeetService } = require('./dist/services/StrangersMeetService');

(async () => {
    try {
        const result = await StrangersMeetService.getAdminHostCancellations({
            status: 'all',
            page: 1,
            limit: 20,
        });
        console.log('Success! Result total:', result.total);
        console.log('Result counts:', result.counts);
        console.log('Rows sample:', JSON.stringify(result.data.map(d => ({
            id: d.id,
            hostName: d.host ? `${d.host.firstName} ${d.host.lastName}` : null,
            meetSubject: d.meet?.subject,
            hostDepositAmount: d.hostDepositAmount,
            totalCollectedAmount: d.totalCollectedAmount,
            status: d.status,
            hostPayoutDetails: d.hostPayoutDetails
        })), null, 2));
        process.exit(0);
    } catch (err) {
        console.error('Error fetching admin host cancellations:', err);
        process.exit(1);
    }
})();
