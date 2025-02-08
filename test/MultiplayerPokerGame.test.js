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

    // Helper function to create a game state
    function createGameState(overrides = {}) {
        const baseState = {
            encryptedDeck: "0x",
            encryptedHands: Array(N_PLAYERS).fill("0x"),
            bets: Array(N_PLAYERS).fill(ethers.utils.parseEther("0.2")),
            currentRound: 0,
            encryptedCommunityCards: "0x",
            currentPlayer: 0,
            folded: Array(N_PLAYERS).fill(false),
            commitments: Array(N_PLAYERS).fill("0x"),
            openings: Array(N_PLAYERS).fill("0x")
        };

        // Deep merge arrays
        const state = { ...baseState };
        for (const key in overrides) {
            if (Array.isArray(overrides[key])) {
                state[key] = overrides[key].map(val => {
                    if (typeof val === 'string' && val.startsWith('0.')) {
                        return ethers.utils.parseEther(val);
                    }
                    return val;
                });
            } else {
                state[key] = overrides[key];
            }
        }
        
        return state;
    }

    // Helper function to create a contract state
    function createContractState(gameStateOverrides = {}, stateOverrides = {}) {
        const gameState = createGameState(gameStateOverrides);
        
        const baseState = {
            mode: "exec",
            id: 0,
            tt: "0x",
            t: Math.floor(Date.now() / 1000),
            L: Array(N_PLAYERS).fill(true),
            tv: "0x",
            b: Array(N_PLAYERS).fill(ethers.utils.parseEther("1")),
            B: Array(N_PLAYERS).fill(0),
            game: gameState
        };

        // Deep merge arrays
        const state = { ...baseState };
        for (const key in stateOverrides) {
            if (Array.isArray(stateOverrides[key])) {
                state[key] = stateOverrides[key].map(val => {
                    if (typeof val === 'string' && val.startsWith('0.')) {
                        return ethers.utils.parseEther(val);
                    }
                    return val;
                });
            } else if (key === 'game') {
                state[key] = createGameState(stateOverrides[key]);
            } else {
                state[key] = stateOverrides[key];
            }
        }

        // Encode the state using defaultAbiCoder
        return ethers.utils.defaultAbiCoder.encode(
            [
                "tuple(string mode, uint256 id, bytes tt, uint256 t, bool[] L, bytes tv, uint256[] b, uint256[] B, " +
                "tuple(bytes encryptedDeck, bytes[] encryptedHands, uint256[] bets, uint8 currentRound, " +
                "bytes encryptedCommunityCards, uint8 currentPlayer, bool[] folded, bytes[] commitments, bytes[] openings) game)"
            ],
            [state]
        );
    }

    beforeEach(async function () {
        [owner, addr1, addr2, addr3] = await ethers.getSigners();

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
            // Create a state where all players have equal bets
            const gameState = createGameState({
                bets: [ethers.utils.parseEther("0.2"), ethers.utils.parseEther("0.2"), ethers.utils.parseEther("0.2")],
                currentPlayer: 0
            });
            const state = createContractState({ ...gameState });

            // Encode the current state as the validation function
            const validationFunction = ethers.utils.defaultAbiCoder.encode(
                ["tuple(string,uint256,bytes,uint256,bool[],bytes,uint256[],uint256[],tuple(bytes,bytes[],uint256[],uint8,bytes,uint8,bool[],bytes[],bytes[]))"],
                [state]
            );

            // Create a check move
            const moveData = ethers.utils.defaultAbiCoder.encode(
                ["uint8", "uint256", "bytes", "bytes"],
                [0, 0, "0x", "0x"] // moveType = 0 (check), amount = 0, signature = empty, mpcData = empty
            );

            // Verify the move is valid
            const isValid = await multiplayerPokerGame.verifyTranscript(
                moveData,  // extension
                "0x",     // currentTranscript (empty for this test)
                validationFunction
            );

            expect(isValid).to.be.true;
        });

        it("Should reject check when bets are not equal", async function () {
            // Create a state where player 1 has bet more than others
            const bets = [
                ethers.utils.parseEther("0.2"),  // Current player
                ethers.utils.parseEther("0.4"),  // Previous player raised
                ethers.utils.parseEther("0.2")
            ];
            console.log("Check validation test:");
            console.log("Bets array:", bets.map(b => ethers.utils.formatEther(b)));

            const gameState = createGameState({
                bets: bets,
                currentPlayer: 0  // First player's turn
            });

            console.log("Game state bets:", gameState.bets.map(b => ethers.utils.formatEther(b)));
            const state = {
                mode: "exec",
                id: 0,
                tt: "0x",
                t: Math.floor(Date.now() / 1000),
                L: Array(N_PLAYERS).fill(true),
                tv: "0x",
                b: Array(N_PLAYERS).fill(ethers.utils.parseEther("1")),
                B: Array(N_PLAYERS).fill(0),
                game: gameState
            };

            // Encode the current state as the validation function
            const validationFunction = ethers.utils.defaultAbiCoder.encode(
                ["tuple(string mode, uint256 id, bytes tt, uint256 t, bool[] L, bytes tv, uint256[] b, uint256[] B, " +
                "tuple(bytes encryptedDeck, bytes[] encryptedHands, uint256[] bets, uint8 currentRound, " +
                "bytes encryptedCommunityCards, uint8 currentPlayer, bool[] folded, bytes[] commitments, bytes[] openings) game)"],
                [state]
            );

            // Create a check move (should fail since there's a higher bet)
            const moveData = ethers.utils.defaultAbiCoder.encode(
                ["uint8", "uint256", "bytes", "bytes"],
                [0, 0, "0x", "0x"]
            );

            // Verify the move is invalid
            const isValid = await multiplayerPokerGame.verifyTranscript(
                moveData,
                "0x",
                validationFunction
            );

            expect(isValid).to.be.false;
        });

        it("Should validate bet moves correctly", async function () {
            // Create a state where current player can bet
            const gameState = createGameState({
                bets: [
                    ethers.utils.parseEther("0.2"),  // Current player
                    ethers.utils.parseEther("0.2"),
                    ethers.utils.parseEther("0.2")
                ],
                currentPlayer: 0
            });
            const state = createContractState({ ...gameState });

            // Encode the current state as the validation function
            const validationFunction = ethers.utils.defaultAbiCoder.encode(
                ["tuple(string,uint256,bytes,uint256,bool[],bytes,uint256[],uint256[],tuple(bytes,bytes[],uint256[],uint8,bytes,uint8,bool[],bytes[],bytes[]))"],
                [state]
            );

            // Create a bet move (raising to 0.4 ETH)
            const moveData = ethers.utils.defaultAbiCoder.encode(
                ["uint8", "uint256", "bytes", "bytes"],
                [1, ethers.utils.parseEther("0.4"), "0x", "0x"]
            );

            // Verify the move is valid
            const isValid = await multiplayerPokerGame.verifyTranscript(
                moveData,
                "0x",
                validationFunction
            );

            expect(isValid).to.be.true;
        });

        it("Should reject insufficient bets", async function () {
            // Create a state where player 0 has bet 0.4 ETH
            const bets = [
                ethers.utils.parseEther("0.4"),  // Previous player bet 0.4
                ethers.utils.parseEther("0.2"),  // Current player
                ethers.utils.parseEther("0.2")
            ];
            console.log("Insufficient bet test:");
            console.log("Bets array:", bets.map(b => ethers.utils.formatEther(b)));

            const gameState = createGameState({
                bets: bets,
                currentPlayer: 1  // Second player's turn
            });

            console.log("Game state bets:", gameState.bets.map(b => ethers.utils.formatEther(b)));
            const state = {
                mode: "exec",
                id: 0,
                tt: "0x",
                t: Math.floor(Date.now() / 1000),
                L: Array(N_PLAYERS).fill(true),
                tv: "0x",
                b: Array(N_PLAYERS).fill(ethers.utils.parseEther("1")),
                B: Array(N_PLAYERS).fill(0),
                game: gameState
            };

            // Encode the current state as the validation function
            const validationFunction = ethers.utils.defaultAbiCoder.encode(
                ["tuple(string mode, uint256 id, bytes tt, uint256 t, bool[] L, bytes tv, uint256[] b, uint256[] B, " +
                "tuple(bytes encryptedDeck, bytes[] encryptedHands, uint256[] bets, uint8 currentRound, " +
                "bytes encryptedCommunityCards, uint8 currentPlayer, bool[] folded, bytes[] commitments, bytes[] openings) game)"],
                [state]
            );

            // Create a bet move (betting 0.3 ETH - less than current max of 0.4)
            const moveData = ethers.utils.defaultAbiCoder.encode(
                ["uint8", "uint256", "bytes", "bytes"],
                [1, ethers.utils.parseEther("0.3"), "0x", "0x"]
            );

            // Verify the move is invalid
            const isValid = await multiplayerPokerGame.verifyTranscript(
                moveData,
                "0x",
                validationFunction
            );

            expect(isValid).to.be.false;
        });

        it("Should validate fold moves correctly", async function () {
            // Create a state where player can fold
            const gameState = createGameState({
                bets: [ethers.utils.parseEther("0.4"), ethers.utils.parseEther("0.2"), ethers.utils.parseEther("0.2")],
                currentPlayer: 1
            });
            const state = createContractState({ ...gameState });

            // Encode the current state as the validation function
            const validationFunction = ethers.utils.defaultAbiCoder.encode(
                ["tuple(string,uint256,bytes,uint256,bool[],bytes,uint256[],uint256[],tuple(bytes,bytes[],uint256[],uint8,bytes,uint8,bool[],bytes[],bytes[]))"],
                [state]
            );

            // Create a fold move
            const moveData = ethers.utils.defaultAbiCoder.encode(
                ["uint8", "uint256", "bytes", "bytes"],
                [2, 0, "0x", "0x"]
            );

            // Verify the move is valid
            const isValid = await multiplayerPokerGame.verifyTranscript(
                moveData,
                "0x",
                validationFunction
            );

            expect(isValid).to.be.true;
        });
    });
}); 