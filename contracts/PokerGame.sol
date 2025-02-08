// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract PokerGame {
    struct Player {
        address addr;
        uint256 chips;
        bool isActive;
        uint8[2] hand;
        bool hasCommitted;
        bool hasRevealed;
    }

    struct GameState {
        uint8[5] communityCards;
        uint256 pot;
        uint256 currentBet;
        uint8 currentPlayer;
        uint256 roundDeadline;
        GamePhase phase;
        uint8[52] encryptedDeck;
        uint8 currentCardIndex;
        address firstPlayer;
        uint256 lastBetAmount;
        uint8 communityCardsDealt;
        Player[] players;
        mapping(address => uint8[2]) selectedCards;
        mapping(address => uint256) bets;
    }

    enum GamePhase {
        Joining,
        FirstPlayerEncryption,
        SecondPlayerCardSelection,
        FirstPlayerDecryption,
        SecondPlayerCardEncryption,
        FirstPlayerCardDecryption,
        SecondPlayerOwnCardSelection,
        SecondPlayerDeckSort,
        DeckEncryption,
        PreFlopBetting,
        FlopDealing,
        FlopBetting,
        TurnDealing,
        TurnBetting,
        RiverDealing,
        RiverBetting,
        ShowDown
    }

    mapping(uint256 => GameState) public games;
    uint256 public currentGameId;
    uint256 public constant TURN_TIME = 5 minutes;
    uint256 public buyInAmount = 1 ether;
    uint8 public constant MAX_PLAYERS = 2;
    
    mapping(address => uint256) public playerGameId; // Track which game a player is in

    event GameCreated(uint256 gameId);
    event PlayerJoined(uint256 gameId, address player);
    event NewRound(uint256 gameId, uint256 timestamp);
    event PlayerBet(uint256 gameId, address player, uint256 amount);
    event PlayerFolded(uint256 gameId, address player);
    event DeckEncrypted(uint256 gameId, address player);
    event CardsSelected(uint256 gameId, address player);
    event CardsDecrypted(uint256 gameId, address player);
    event CommunityCardsDealt(uint256 gameId, uint8 count);

    constructor() {
        currentGameId = 0;
        createNewGame();
    }

    function createNewGame() public {
        currentGameId++;
        games[currentGameId].phase = GamePhase.Joining;
        emit GameCreated(currentGameId);
    }

    function joinGame(uint256 gameId) external payable {
        require(msg.value == buyInAmount, "Must send exact buy-in amount");
        require(games[gameId].players.length < MAX_PLAYERS, "Game is full");
        require(!isPlayerInGame(msg.sender), "Already in a game");
        require(games[gameId].phase == GamePhase.Joining, "Game in progress");

        Player memory newPlayer = Player({
            addr: msg.sender,
            chips: msg.value,
            isActive: true,
            hand: [0, 0],
            hasCommitted: false,
            hasRevealed: false
        });

        games[gameId].players.push(newPlayer);
        playerGameId[msg.sender] = gameId;

        if (games[gameId].players.length == 1) {
            games[gameId].firstPlayer = msg.sender;
        }

        emit PlayerJoined(gameId, msg.sender);

        if (games[gameId].players.length == MAX_PLAYERS) {
            games[gameId].phase = GamePhase.FirstPlayerEncryption;
            if (games[gameId].players.length == MAX_PLAYERS && gameId == currentGameId) {
                createNewGame();
            }
        }
    }

    function getCurrentGameId() external view returns (uint256) {
        return currentGameId;
    }

    function getPlayerGameId(address player) external view returns (uint256) {
        return playerGameId[player];
    }

    function isPlayerInGame(address playerAddress) public view returns (bool) {
        uint256 gameId = playerGameId[playerAddress];
        if (gameId == 0) return false;
        
        for (uint i = 0; i < games[gameId].players.length; i++) {
            if (games[gameId].players[i].addr == playerAddress) {
                return true;
            }
        }
        return false;
    }

    function submitEncryptedDeck(uint256 gameId, uint8[52] calldata _encryptedDeck) external {
        require(isPlayerInGame(msg.sender), "Not in game");
        require(playerGameId[msg.sender] == gameId, "Not in this game");
        require(
            games[gameId].phase == GamePhase.FirstPlayerEncryption || 
            games[gameId].phase == GamePhase.DeckEncryption, 
            "Wrong phase"
        );
        
        if (games[gameId].phase == GamePhase.FirstPlayerEncryption) {
            require(msg.sender == games[gameId].firstPlayer, "Not first player");
            games[gameId].phase = GamePhase.SecondPlayerCardSelection;
        } else {
            require(msg.sender != games[gameId].firstPlayer, "Not second player");
            games[gameId].phase = GamePhase.PreFlopBetting;
            games[gameId].currentPlayer = 1;
            games[gameId].lastBetAmount = 0;
        }

        games[gameId].encryptedDeck = _encryptedDeck;
        emit DeckEncrypted(gameId, msg.sender);
    }

    function selectCards(uint256 gameId, uint8[2] calldata _selectedIndices) external {
        require(isPlayerInGame(msg.sender), "Not in game");
        require(playerGameId[msg.sender] == gameId, "Not in this game");
        require(games[gameId].phase == GamePhase.SecondPlayerCardSelection, "Wrong phase");
        require(msg.sender != games[gameId].firstPlayer, "Not second player");

        games[gameId].selectedCards[msg.sender] = _selectedIndices;
        games[gameId].phase = GamePhase.FirstPlayerDecryption;
        emit CardsSelected(gameId, msg.sender);
    }

    function decryptCards(uint256 gameId, uint8[2] calldata _decryptedCards, address forPlayer) external {
        require(isPlayerInGame(msg.sender), "Not in game");
        require(playerGameId[msg.sender] == gameId, "Not in this game");
        require(msg.sender == games[gameId].firstPlayer, "Not first player");
        require(
            (games[gameId].phase == GamePhase.FirstPlayerDecryption && forPlayer != games[gameId].firstPlayer) ||
            (games[gameId].phase == GamePhase.FirstPlayerCardDecryption && forPlayer == games[gameId].firstPlayer),
            "Wrong phase"
        );
        
        Player storage targetPlayer = getPlayer(gameId, forPlayer);
        targetPlayer.hand = _decryptedCards;
        
        if (games[gameId].phase == GamePhase.FirstPlayerDecryption) {
            games[gameId].phase = GamePhase.SecondPlayerCardEncryption;
        } else {
            games[gameId].phase = GamePhase.SecondPlayerOwnCardSelection;
        }
        
        emit CardsDecrypted(gameId, msg.sender);
    }

    function selectOwnCards(uint256 gameId, uint8[2] calldata _selectedIndices) external {
        require(isPlayerInGame(msg.sender), "Not in game");
        require(playerGameId[msg.sender] == gameId, "Not in this game");
        require(games[gameId].phase == GamePhase.SecondPlayerOwnCardSelection, "Wrong phase");
        require(msg.sender != games[gameId].firstPlayer, "Not second player");

        games[gameId].selectedCards[msg.sender] = _selectedIndices;
        games[gameId].phase = GamePhase.SecondPlayerDeckSort;
        emit CardsSelected(gameId, msg.sender);
    }

    function submitSortedDeck(uint256 gameId, uint8[52] calldata _sortedDeck) external {
        require(isPlayerInGame(msg.sender), "Not in game");
        require(playerGameId[msg.sender] == gameId, "Not in this game");
        require(games[gameId].phase == GamePhase.SecondPlayerDeckSort, "Wrong phase");
        require(msg.sender != games[gameId].firstPlayer, "Not second player");

        games[gameId].encryptedDeck = _sortedDeck;
        games[gameId].phase = GamePhase.DeckEncryption;
        emit DeckEncrypted(gameId, msg.sender);
    }

    function dealCommunityCards(uint256 gameId) external {
        require(isPlayerInGame(msg.sender), "Not in game");
        require(playerGameId[msg.sender] == gameId, "Not in this game");
        require(
            games[gameId].phase == GamePhase.FlopDealing ||
            games[gameId].phase == GamePhase.TurnDealing ||
            games[gameId].phase == GamePhase.RiverDealing,
            "Wrong phase"
        );
        require(msg.sender == games[gameId].firstPlayer, "Not first player");

        if (games[gameId].phase == GamePhase.FlopDealing) {
            // Deal 3 cards for flop
            for(uint8 i = 0; i < 3; i++) {
                games[gameId].communityCards[i] = games[gameId].encryptedDeck[games[gameId].currentCardIndex++];
            }
            games[gameId].communityCardsDealt = 3;
            games[gameId].phase = GamePhase.FlopBetting;
        } else if (games[gameId].phase == GamePhase.TurnDealing) {
            // Deal 1 card for turn
            games[gameId].communityCards[3] = games[gameId].encryptedDeck[games[gameId].currentCardIndex++];
            games[gameId].communityCardsDealt = 4;
            games[gameId].phase = GamePhase.TurnBetting;
        } else {
            // Deal 1 card for river
            games[gameId].communityCards[4] = games[gameId].encryptedDeck[games[gameId].currentCardIndex++];
            games[gameId].communityCardsDealt = 5;
            games[gameId].phase = GamePhase.RiverBetting;
        }

        games[gameId].currentPlayer = 1; // Second player starts betting
        games[gameId].lastBetAmount = 0;
        games[gameId].currentBet = 0;
        
        emit CommunityCardsDealt(gameId, games[gameId].communityCardsDealt);
    }

    function placeBet(uint256 gameId) external payable {
        require(isPlayerInGame(msg.sender), "Not in game");
        require(playerGameId[msg.sender] == gameId, "Not in this game");
        require(
            games[gameId].phase == GamePhase.PreFlopBetting ||
            games[gameId].phase == GamePhase.FlopBetting ||
            games[gameId].phase == GamePhase.TurnBetting ||
            games[gameId].phase == GamePhase.RiverBetting,
            "Not betting phase"
        );
        require(msg.value >= games[gameId].currentBet, "Bet too small");

        games[gameId].bets[msg.sender] += msg.value;
        games[gameId].pot += msg.value;
        games[gameId].currentBet = msg.value;
        games[gameId].lastBetAmount = msg.value;

        // Move to next player or next round
        games[gameId].currentPlayer = uint8((uint256(games[gameId].currentPlayer) + 1) % games[gameId].players.length);
        
        // If we're back to the first better and bets are equal, move to next phase
        if (games[gameId].currentPlayer == 1 && areBetsEqual(gameId)) {
            moveToNextPhase(gameId);
        }
        
        emit PlayerBet(gameId, msg.sender, msg.value);
    }

    function fold(uint256 gameId) external {
        require(isPlayerInGame(msg.sender), "Not in game");
        require(playerGameId[msg.sender] == gameId, "Not in this game");
        require(
            games[gameId].phase == GamePhase.PreFlopBetting ||
            games[gameId].phase == GamePhase.FlopBetting ||
            games[gameId].phase == GamePhase.TurnBetting ||
            games[gameId].phase == GamePhase.RiverBetting,
            "Not betting phase"
        );

        getPlayer(gameId, msg.sender).isActive = false;
        emit PlayerFolded(gameId, msg.sender);

        if (getActivePlayerCount(gameId) == 1) {
            endRound(gameId);
        }
    }

    function encryptCardsForFirstPlayer(uint256 gameId, uint8[2] calldata _encryptedCards) external {
        require(isPlayerInGame(msg.sender), "Not in game");
        require(playerGameId[msg.sender] == gameId, "Not in this game");
        require(games[gameId].phase == GamePhase.SecondPlayerCardEncryption, "Wrong phase");
        require(msg.sender != games[gameId].firstPlayer, "Not second player");

        games[gameId].selectedCards[games[gameId].firstPlayer] = _encryptedCards;
        games[gameId].phase = GamePhase.FirstPlayerCardDecryption;
        emit CardsSelected(gameId, msg.sender);
    }

    // Helper functions
    function getPlayer(uint256 gameId, address playerAddress) private view returns (Player storage) {
        for (uint i = 0; i < games[gameId].players.length; i++) {
            if (games[gameId].players[i].addr == playerAddress) {
                return games[gameId].players[i];
            }
        }
        revert("Player not found");
    }

    function getActivePlayerCount(uint256 gameId) private view returns (uint256) {
        uint256 count = 0;
        for (uint i = 0; i < games[gameId].players.length; i++) {
            if (games[gameId].players[i].isActive) {
                count++;
            }
        }
        return count;
    }

    function endRound(uint256 gameId) private {
        // For now, just reset the game state
        games[gameId].phase = GamePhase.Joining;
        delete games[gameId].players;
        games[gameId].pot = 0;
        games[gameId].currentBet = 0;
        games[gameId].lastBetAmount = 0;
        games[gameId].currentCardIndex = 0;
        games[gameId].communityCardsDealt = 0;
        for(uint8 i = 0; i < 5; i++) {
            games[gameId].communityCards[i] = 0;
        }
    }

    function areBetsEqual(uint256 gameId) private view returns (bool) {
        uint256 firstBet = games[gameId].bets[games[gameId].players[0].addr];
        uint256 secondBet = games[gameId].bets[games[gameId].players[1].addr];
        return firstBet == secondBet;
    }

    function moveToNextPhase(uint256 gameId) private {
        if (games[gameId].phase == GamePhase.PreFlopBetting) {
            games[gameId].phase = GamePhase.FlopDealing;
        } else if (games[gameId].phase == GamePhase.FlopBetting) {
            games[gameId].phase = GamePhase.TurnDealing;
        } else if (games[gameId].phase == GamePhase.TurnBetting) {
            games[gameId].phase = GamePhase.RiverDealing;
        } else if (games[gameId].phase == GamePhase.RiverBetting) {
            games[gameId].phase = GamePhase.ShowDown;
        }
        games[gameId].currentBet = 0;
        games[gameId].lastBetAmount = 0;
    }
}