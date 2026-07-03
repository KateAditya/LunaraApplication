require('dotenv').config();
const sequelize = require('./dist/config/database').default;
const PartyPlan = require('./dist/models/PartyPlan').default;
const PartyPlanRequest = require('./dist/models/PartyPlanRequest').default;
const UserPenalty = require('./dist/models/UserPenalty').default;

async function syncNewModels() {
    try {
        console.log("Synchronizing PartyPlan...");
        await PartyPlan.sync({ alter: true });
        
        console.log("Synchronizing PartyPlanRequest...");
        await PartyPlanRequest.sync({ alter: true });

        console.log("Synchronizing UserPenalty...");
        await UserPenalty.sync({ alter: true });

        console.log("All new models synchronized successfully!");
        process.exit(0);
    } catch (err) {
        console.error("Error synchronizing new models:", err);
        process.exit(1);
    }
}

syncNewModels();
