const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MultiPlayerPokerGame", function () {
    let MultiPlayerPokerGame;
    let game;
    let owner;
    let player1;
    let player2;
    let player3;
    let player4;
    const PENALTY_AMOUNT = ethers.utils.parseEther("1.0"); // 1 ETH penalty
    const DELTA_TIME = 3600; // 1 hour for timeouts

    beforeEach(async function () {
        [owner, player1, player2, player3, player4] = await ethers.getSigners();
        
        MultiPlayerPokerGame = await ethers.getContractFactory("MultiPlayerPokerGame");
        game = await MultiPlayerPokerGame.deploy(PENALTY_AMOUNT, DELTA_TIME);
        await game.deployed();
    });

    describe("Initialization", function () {
        it("Should initialize with correct parameters", async function () {
            expect(await game.penaltyAmount()).to.equal(PENALTY_AMOUNT);
            expect(await game.deltaTime()).to.equal(DELTA_TIME);
            expect(await game.getGameState()).to.equal(0); // INIT state
        });

        it("Should allow players to join with correct deposit", async function () {
            const requiredDeposit = PENALTY_AMOUNT.mul(3); // (n-1)q for n=4 players
            
            await expect(game.connect(player1).joinGame({value: requiredDeposit}))
                .to.emit(game, "PlayerJoined")
                .withArgs(player1.address);

            const player1State = await game.players(player1.address);
            expect(player1State.hasJoined).to.be.true;
            expect(player1State.deposit).to.equal(requiredDeposit);
        });

        it("Should reject players joining with incorrect deposit", async function () {
            const incorrectDeposit = PENALTY_AMOUNT.mul(2);
            
            await expect(
                game.connect(player1).joinGame({value: incorrectDeposit})
            ).to.be.revertedWith("Incorrect deposit amount");
        });

        it("Should allow a player to exit during INIT state", async function () {
            const requiredDeposit = PENALTY_AMOUNT.mul(3);
            await game.connect(player1).joinGame({value: requiredDeposit});
            
            await expect(game.connect(player1).exitGame())
                .to.emit(game, "PlayerExit")
                .withArgs(player1.address);
            
            const player1State = await game.players(player1.address);
            expect(player1State.hasExited).to.be.true;
        });
    });

    describe("State Management", function () {
        beforeEach(async function () {
            const requiredDeposit = PENALTY_AMOUNT.mul(3);
            await game.connect(player1).joinGame({value: requiredDeposit});
            await game.connect(player2).joinGame({value: requiredDeposit});
            await game.connect(player3).joinGame({value: requiredDeposit});
            await game.connect(player4).joinGame({value: requiredDeposit});
        });

        it("Should track game state correctly", async function () {
            expect(await game.getGameState()).to.equal(1); // SETUP state after all players joined
        });

        it("Should allow a player to exit during SETUP state", async function () {
            await expect(game.connect(player1).exitGame())
                .to.emit(game, "PlayerExit")
                .withArgs(player1.address);
            
            const player1State = await game.players(player1.address);
            expect(player1State.hasExited).to.be.true;
        });

        it("Should handle parameter agreement phase", async function () {
            // Create a mock transcript validation function (simplified for testing)
            const mockTranscriptHash = ethers.utils.id("mockTranscript");
            
            await expect(game.connect(player1).agreeOnParameters(mockTranscriptHash))
                .to.emit(game, "ParametersAgreed")
                .withArgs(player1.address, mockTranscriptHash);
            
            const agreementState = await game.parameterAgreements(player1.address);
            expect(agreementState).to.equal(mockTranscriptHash);
        });
    });
}); 