// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title MultiPlayerPokerGame
 * @dev Implementation of a multiplayer poker game using MPC with penalties
 */
contract MultiPlayerPokerGame {
    // Constants
    uint8 public constant MAX_PLAYERS = 4;
    
    // State variables
    uint256 public immutable penaltyAmount;
    uint256 public immutable deltaTime;
    address[] private playerAddresses;
    
    enum GameState {
        INIT,       // Initial state, waiting for players
        SETUP,      // All players joined, setting up parameters
        EXEC,       // Executing the game
        EXIT,       // Someone requested exit
        PAYOUT,     // Paying out winners
        ABORT,      // Game aborted due to violation
        INACTIVE    // Game completed
    }
    
    struct Player {
        bool hasJoined;
        bool hasExited;
        uint256 deposit;
        bytes32 parameterAgreement;
        bool hasAgreedParameters;
    }
    
    GameState public gameState;
    mapping(address => Player) public players;
    uint256 public joinedPlayerCount;
    mapping(address => bytes32) public parameterAgreements;
    
    // Events
    event PlayerJoined(address player);
    event PlayerExit(address player);
    event ParametersAgreed(address player, bytes32 transcriptHash);
    
    constructor(uint256 _penaltyAmount, uint256 _deltaTime) {
        require(_penaltyAmount > 0, "Penalty amount must be positive");
        require(_deltaTime > 0, "Delta time must be positive");
        
        penaltyAmount = _penaltyAmount;
        deltaTime = _deltaTime;
        gameState = GameState.INIT;
    }
    
    function joinGame() external payable {
        require(gameState == GameState.INIT, "Game not in initialization state");
        require(!players[msg.sender].hasJoined, "Player already joined");
        require(joinedPlayerCount < MAX_PLAYERS, "Game is full");
        
        uint256 requiredDeposit = penaltyAmount * (MAX_PLAYERS - 1);
        require(msg.value == requiredDeposit, "Incorrect deposit amount");
        
        players[msg.sender] = Player({
            hasJoined: true,
            hasExited: false,
            deposit: msg.value,
            parameterAgreement: bytes32(0),
            hasAgreedParameters: false
        });
        
        playerAddresses.push(msg.sender);
        joinedPlayerCount++;
        emit PlayerJoined(msg.sender);
        
        if (joinedPlayerCount == MAX_PLAYERS) {
            gameState = GameState.SETUP;
        }
    }
    
    function exitGame() external {
        require(players[msg.sender].hasJoined, "Player not in game");
        require(!players[msg.sender].hasExited, "Player already exited");
        require(gameState == GameState.INIT || gameState == GameState.SETUP, 
                "Can only exit during INIT or SETUP");
        
        players[msg.sender].hasExited = true;
        emit PlayerExit(msg.sender);
        
        // Return deposit
        uint256 deposit = players[msg.sender].deposit;
        players[msg.sender].deposit = 0;
        payable(msg.sender).transfer(deposit);
    }
    
    function agreeOnParameters(bytes32 transcriptHash) external {
        require(players[msg.sender].hasJoined, "Player not in game");
        require(!players[msg.sender].hasExited, "Player has exited");
        require(gameState == GameState.SETUP, "Not in setup phase");
        require(!players[msg.sender].hasAgreedParameters, "Already agreed to parameters");
        
        players[msg.sender].parameterAgreement = transcriptHash;
        players[msg.sender].hasAgreedParameters = true;
        parameterAgreements[msg.sender] = transcriptHash;
        
        emit ParametersAgreed(msg.sender, transcriptHash);
        
        // Check if all players have agreed
        bool allAgreed = true;
        address[] memory activePlayers = getJoinedPlayers();
        bytes32 firstHash = parameterAgreements[activePlayers[0]];
        
        for (uint i = 0; i < activePlayers.length; i++) {
            if (!players[activePlayers[i]].hasAgreedParameters || 
                parameterAgreements[activePlayers[i]] != firstHash) {
                allAgreed = false;
                break;
            }
        }
        
        if (allAgreed) {
            gameState = GameState.EXEC;
        }
    }
    
    function getGameState() external view returns (GameState) {
        return gameState;
    }
    
    function getJoinedPlayers() public view returns (address[] memory) {
        address[] memory activePlayers = new address[](joinedPlayerCount);
        uint256 activeCount = 0;
        
        for (uint256 i = 0; i < playerAddresses.length; i++) {
            address player = playerAddresses[i];
            if (players[player].hasJoined && !players[player].hasExited) {
                activePlayers[activeCount] = player;
                activeCount++;
            }
        }
        
        // Resize array to actual number of active players
        assembly {
            mstore(activePlayers, activeCount)
        }
        
        return activePlayers;
    }
} 