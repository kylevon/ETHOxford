const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MultiplayerPokerGame", function () {
    let multiplayerPokerGame;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    const DELTA = 100; // Time window for actions
    const N_PLAYERS = 3;
    const PENALTY = ethers.utils.parseEther("1"); // 1 ETH penalty
    const SMALL_BLIND = ethers.utils.parseEther("0.1"); // 0.1 ETH
    const BIG_BLIND = ethers.utils.parseEther("0.2"); // 0.2 ETH

    // Helper function to create mock encrypted data
    function mockEncrypt(data) {
        return ethers.utils.hexlify(ethers.utils.randomBytes(32));
    }

    beforeEach(async function () {
        [owner, addr1, addr2, addr3] = await ethers.getSigners();

        // Deploy the contract
        const MultiplayerPokerGame = await ethers.getContractFactory("MultiplayerPokerGame");
        multiplayerPokerGame = await MultiplayerPokerGame.deploy(
            N_PLAYERS,
            DELTA,
            PENALTY,
            SMALL_BLIND,
            BIG_BLIND
        );
        await multiplayerPokerGame.deployed();
    });

    describe("Constructor", function () {
        it("Should set the right parameters", async function () {
            expect(await multiplayerPokerGame.n()).to.equal(N_PLAYERS);
            expect(await multiplayerPokerGame.DELTA()).to.equal(DELTA);
            expect(await multiplayerPokerGame.q()).to.equal(PENALTY);
            expect(await multiplayerPokerGame.SMALL_BLIND()).to.equal(SMALL_BLIND);
            expect(await multiplayerPokerGame.BIG_BLIND()).to.equal(BIG_BLIND);
        });

        it("Should reject invalid number of players", async function () {
            const MultiplayerPokerGame = await ethers.getContractFactory("MultiplayerPokerGame");
            await expect(
                MultiplayerPokerGame.deploy(1, DELTA, PENALTY, SMALL_BLIND, BIG_BLIND)
            ).to.be.revertedWith("Invalid number of players");
            
            await expect(
                MultiplayerPokerGame.deploy(11, DELTA, PENALTY, SMALL_BLIND, BIG_BLIND)
            ).to.be.revertedWith("Invalid number of players");
        });
    });

    describe("State Transitions", function () {
        it("Should handle exit from init state", async function () {
            // Create game state components with encrypted data
            const gameState = [
                mockEncrypt("deck"), // encryptedDeck
                Array(N_PLAYERS).fill(0).map(() => mockEncrypt("hand")), // encryptedHands
                Array(N_PLAYERS).fill(0), // bets
                0, // currentRound
                mockEncrypt("community"), // encryptedCommunityCards
                0, // currentPlayer
                Array(N_PLAYERS).fill(false), // folded
                Array(N_PLAYERS).fill("0x"), // commitments
                Array(N_PLAYERS).fill("0x")  // openings
            ];

            // Create state components
            const state = [
                "init", // mode
                0, // id
                "0x", // tt
                Math.floor(Date.now() / 1000), // t
                Array(N_PLAYERS).fill(true), // L
                "0x", // tv
                Array(N_PLAYERS).fill(0), // b
                Array(N_PLAYERS).fill(0), // B
                gameState // game
            ];

            // Encode state
            const encodedState = ethers.utils.defaultAbiCoder.encode(
                ["tuple(string,uint256,bytes,uint256,bool[],bytes,uint256[],uint256[],tuple(bytes,bytes[],uint256[],uint8,bytes,uint8,bool[],bytes[],bytes[]))"],
                [state]
            );

            // Create exit witness
            const exitWitness = ethers.utils.toUtf8Bytes("exit");

            // Call prog function
            const [newState, payout] = await multiplayerPokerGame.prog(
                1, // Player index
                exitWitness,
                Math.floor(Date.now() / 1000),
                encodedState
            );

            // Decode new state
            const decodedState = ethers.utils.defaultAbiCoder.decode(
                ["tuple(string,uint256,bytes,uint256,bool[],bytes,uint256[],uint256[],tuple(bytes,bytes[],uint256[],uint8,bytes,uint8,bool[],bytes[],bytes[]))"],
                newState
            )[0];

            // Verify state transition
            expect(decodedState[0]).to.equal("exit"); // mode is first element
            expect(payout).to.equal(0);
        });

        it("Should handle balance updates", async function () {
            // Create game state components with encrypted data
            const gameState = [
                mockEncrypt("deck"), // encryptedDeck
                Array(N_PLAYERS).fill(0).map(() => mockEncrypt("hand")), // encryptedHands
                Array(N_PLAYERS).fill(0), // bets
                0, // currentRound
                mockEncrypt("community"), // encryptedCommunityCards
                0, // currentPlayer
                Array(N_PLAYERS).fill(false), // folded
                Array(N_PLAYERS).fill("0x"), // commitments
                Array(N_PLAYERS).fill("0x")  // openings
            ];

            // Create state components
            const state = [
                "exec", // mode
                0, // id
                "0x", // tt
                Math.floor(Date.now() / 1000), // t
                Array(N_PLAYERS).fill(true), // L
                "0x", // tv
                Array(N_PLAYERS).fill(ethers.utils.parseEther("1")), // b
                Array(N_PLAYERS).fill(0), // B
                gameState // game
            ];

            // Encode state
            const encodedState = ethers.utils.defaultAbiCoder.encode(
                ["tuple(string,uint256,bytes,uint256,bool[],bytes,uint256[],uint256[],tuple(bytes,bytes[],uint256[],uint8,bytes,uint8,bool[],bytes[],bytes[]))"],
                [state]
            );

            // Create update parameters
            const newBalance = [
                ethers.utils.parseEther("1.5"),
                ethers.utils.parseEther("1"),
                ethers.utils.parseEther("1")
            ];
            const signatures = Array(N_PLAYERS).fill("0x"); // Mock signatures
            const amount = ethers.utils.parseEther("0.5");

            // Encode update parameters
            const updateWitness = ethers.utils.defaultAbiCoder.encode(
                ["uint256[]", "bytes[]", "uint256"],
                [newBalance, signatures, amount]
            );

            // Call update function
            const newState = await multiplayerPokerGame.update(
                0, // Player index
                updateWitness,
                Math.floor(Date.now() / 1000),
                encodedState
            );

            // Decode new state
            const decodedState = ethers.utils.defaultAbiCoder.decode(
                ["tuple(string,uint256,bytes,uint256,bool[],bytes,uint256[],uint256[],tuple(bytes,bytes[],uint256[],uint8,bytes,uint8,bool[],bytes[],bytes[]))"],
                newState
            )[0];

            // Verify balance update
            expect(decodedState[6][0]).to.equal(newBalance[0]); // b[0]
            expect(decodedState[7][0]).to.equal(amount); // B[0]
        });
    });

    describe("Move Validation", function () {
        it("Should validate check moves correctly", async function () {
            // Create game state components with encrypted data
            const gameState = [
                mockEncrypt("deck"), // encryptedDeck
                Array(N_PLAYERS).fill(0).map(() => mockEncrypt("hand")), // encryptedHands
                [ethers.utils.parseEther("0.2"), ethers.utils.parseEther("0.2"), ethers.utils.parseEther("0.2")], // bets
                0, // currentRound
                mockEncrypt("community"), // encryptedCommunityCards
                0, // currentPlayer
                Array(N_PLAYERS).fill(false), // folded
                Array(N_PLAYERS).fill("0x"), // commitments
                Array(N_PLAYERS).fill("0x")  // openings
            ];

            // Create state components
            const state = [
                "exec", // mode
                0, // id
                "0x", // tt
                Math.floor(Date.now() / 1000), // t
                Array(N_PLAYERS).fill(true), // L
                "0x", // tv
                Array(N_PLAYERS).fill(ethers.utils.parseEther("1")), // b
                Array(N_PLAYERS).fill(0), // B
                gameState // game
            ];

            // Encode a check move
            const moveData = ethers.utils.defaultAbiCoder.encode(
                ["uint8", "uint256", "bytes", "bytes"],
                [0, 0, "0x", "0x"] // moveType = 0 (check), amount = 0, signature = empty, mpcData = empty
            );

            // Encode state
            const encodedState = ethers.utils.defaultAbiCoder.encode(
                ["tuple(string,uint256,bytes,uint256,bool[],bytes,uint256[],uint256[],tuple(bytes,bytes[],uint256[],uint8,bytes,uint8,bool[],bytes[],bytes[]))"],
                [state]
            );

            // Verify the move is valid
            const isValid = await multiplayerPokerGame.callStatic["verifyTranscript"](
                moveData,
                "0x",
                "0x"
            );

            expect(isValid).to.be.true;
        });
    });
}); 