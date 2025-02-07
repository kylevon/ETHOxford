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

    Player[] public players;
    GameState public currentGame;
    uint256 public constant TURN_TIME = 5 minutes;
    uint256 public buyInAmount = 1 ether;
    uint8 public constant MAX_PLAYERS = 2; // Limiting to 2 players for now
    
    mapping(address => bytes32) public commitments;
    mapping(address => uint256) public bets;
    mapping(address => uint8[52]) public encryptedCards;
    mapping(address => uint8[2]) public selectedCards;

    event PlayerJoined(address player);
    event NewRound(uint256 timestamp);
    event PlayerBet(address player, uint256 amount);
    event PlayerFolded(address player);
    event DeckEncrypted(address player);
    event CardsSelected(address player);
    event CardsDecrypted(address player);
    event CommunityCardsDealt(uint8 count);

    constructor() {
        currentGame.phase = GamePhase.Joining;
    }

    function joinGame() external payable {
        require(msg.value == buyInAmount, "Must send exact buy-in amount");
        require(players.length < MAX_PLAYERS, "Game is full");
        require(!isPlayerInGame(msg.sender), "Already in game");
        require(currentGame.phase == GamePhase.Joining, "Game in progress");

        players.push(Player({
            addr: msg.sender,
            chips: msg.value,
            isActive: true,
            hand: [0, 0],
            hasCommitted: false,
            hasRevealed: false
        }));

        if (players.length == 1) {
            currentGame.firstPlayer = msg.sender;
        }

        emit PlayerJoined(msg.sender);

        if (players.length == MAX_PLAYERS) {
            currentGame.phase = GamePhase.FirstPlayerEncryption;
        }
    }

    function submitEncryptedDeck(uint8[52] calldata _encryptedDeck) external {
        require(isPlayerInGame(msg.sender), "Not in game");
        require(currentGame.phase == GamePhase.FirstPlayerEncryption || currentGame.phase == GamePhase.DeckEncryption, "Wrong phase");
        
        if (currentGame.phase == GamePhase.FirstPlayerEncryption) {
            require(msg.sender == currentGame.firstPlayer, "Not first player");
            currentGame.phase = GamePhase.SecondPlayerCardSelection;
        } else {
            require(msg.sender != currentGame.firstPlayer, "Not second player");
            currentGame.phase = GamePhase.PreFlopBetting;
            currentGame.currentPlayer = 1; // Second player starts betting
            currentGame.lastBetAmount = 0;
        }

        encryptedCards[msg.sender] = _encryptedDeck;
        emit DeckEncrypted(msg.sender);
    }

    function selectCards(uint8[2] calldata _selectedIndices) external {
        require(isPlayerInGame(msg.sender), "Not in game");
        require(currentGame.phase == GamePhase.SecondPlayerCardSelection, "Wrong phase");
        require(msg.sender != currentGame.firstPlayer, "Not second player");

        selectedCards[msg.sender] = _selectedIndices;
        currentGame.phase = GamePhase.FirstPlayerDecryption;
        emit CardsSelected(msg.sender);
    }

    function decryptCards(uint8[2] calldata _decryptedCards, address forPlayer) external {
        require(isPlayerInGame(msg.sender), "Not in game");
        require(msg.sender == currentGame.firstPlayer, "Not first player");
        require(
            (currentGame.phase == GamePhase.FirstPlayerDecryption && forPlayer != currentGame.firstPlayer) ||
            (currentGame.phase == GamePhase.FirstPlayerCardDecryption && forPlayer == currentGame.firstPlayer),
            "Wrong phase"
        );
        
        Player storage targetPlayer = getPlayer(forPlayer);
        targetPlayer.hand = _decryptedCards;
        
        if (currentGame.phase == GamePhase.FirstPlayerDecryption) {
            currentGame.phase = GamePhase.SecondPlayerCardEncryption;
        } else {
            currentGame.phase = GamePhase.SecondPlayerOwnCardSelection;
        }
        
        emit CardsDecrypted(msg.sender);
    }

    function selectOwnCards(uint8[2] calldata _selectedIndices) external {
        require(isPlayerInGame(msg.sender), "Not in game");
        require(currentGame.phase == GamePhase.SecondPlayerOwnCardSelection, "Wrong phase");
        require(msg.sender != currentGame.firstPlayer, "Not second player");

        selectedCards[msg.sender] = _selectedIndices;
        currentGame.phase = GamePhase.SecondPlayerDeckSort;
        emit CardsSelected(msg.sender);
    }

    function submitSortedDeck(uint8[52] calldata _sortedDeck) external {
        require(isPlayerInGame(msg.sender), "Not in game");
        require(currentGame.phase == GamePhase.SecondPlayerDeckSort, "Wrong phase");
        require(msg.sender != currentGame.firstPlayer, "Not second player");

        encryptedCards[msg.sender] = _sortedDeck;
        currentGame.phase = GamePhase.DeckEncryption;
        emit DeckEncrypted(msg.sender);
    }

    function dealCommunityCards() external {
        require(isPlayerInGame(msg.sender), "Not in game");
        require(
            currentGame.phase == GamePhase.FlopDealing ||
            currentGame.phase == GamePhase.TurnDealing ||
            currentGame.phase == GamePhase.RiverDealing,
            "Wrong phase"
        );
        require(msg.sender == currentGame.firstPlayer, "Not first player");

        if (currentGame.phase == GamePhase.FlopDealing) {
            // Deal 3 cards for flop
            for(uint8 i = 0; i < 3; i++) {
                currentGame.communityCards[i] = encryptedCards[msg.sender][currentGame.currentCardIndex++];
            }
            currentGame.communityCardsDealt = 3;
            currentGame.phase = GamePhase.FlopBetting;
        } else if (currentGame.phase == GamePhase.TurnDealing) {
            // Deal 1 card for turn
            currentGame.communityCards[3] = encryptedCards[msg.sender][currentGame.currentCardIndex++];
            currentGame.communityCardsDealt = 4;
            currentGame.phase = GamePhase.TurnBetting;
        } else {
            // Deal 1 card for river
            currentGame.communityCards[4] = encryptedCards[msg.sender][currentGame.currentCardIndex++];
            currentGame.communityCardsDealt = 5;
            currentGame.phase = GamePhase.RiverBetting;
        }

        currentGame.currentPlayer = 1; // Second player starts betting
        currentGame.lastBetAmount = 0;
        currentGame.currentBet = 0;
        
        emit CommunityCardsDealt(currentGame.communityCardsDealt);
    }

    function placeBet() external payable {
        require(isPlayerInGame(msg.sender), "Not in game");
        require(
            currentGame.phase == GamePhase.PreFlopBetting ||
            currentGame.phase == GamePhase.FlopBetting ||
            currentGame.phase == GamePhase.TurnBetting ||
            currentGame.phase == GamePhase.RiverBetting,
            "Not betting phase"
        );
        require(msg.value >= currentGame.currentBet, "Bet too small");

        bets[msg.sender] += msg.value;
        currentGame.pot += msg.value;
        currentGame.currentBet = msg.value;
        currentGame.lastBetAmount = msg.value;

        // Move to next player or next round
        currentGame.currentPlayer = uint8((uint256(currentGame.currentPlayer) + 1) % players.length);
        
        // If we're back to the first better and bets are equal, move to next phase
        if (currentGame.currentPlayer == 1 && areBetsEqual()) {
            moveToNextPhase();
        }
        
        emit PlayerBet(msg.sender, msg.value);
    }

    function fold() external {
        require(isPlayerInGame(msg.sender), "Not in game");
        require(
            currentGame.phase == GamePhase.PreFlopBetting ||
            currentGame.phase == GamePhase.FlopBetting ||
            currentGame.phase == GamePhase.TurnBetting ||
            currentGame.phase == GamePhase.RiverBetting,
            "Not betting phase"
        );

        getPlayer(msg.sender).isActive = false;
        emit PlayerFolded(msg.sender);

        if (getActivePlayerCount() == 1) {
            endRound();
        }
    }

    function encryptCardsForFirstPlayer(uint8[2] calldata _encryptedCards) external {
        require(isPlayerInGame(msg.sender), "Not in game");
        require(currentGame.phase == GamePhase.SecondPlayerCardEncryption, "Wrong phase");
        require(msg.sender != currentGame.firstPlayer, "Not second player");

        selectedCards[currentGame.firstPlayer] = _encryptedCards;
        currentGame.phase = GamePhase.FirstPlayerCardDecryption;
        emit CardsSelected(msg.sender);
    }

    // Helper functions
    function getPlayer(address playerAddress) private view returns (Player storage) {
        for (uint i = 0; i < players.length; i++) {
            if (players[i].addr == playerAddress) {
                return players[i];
            }
        }
        revert("Player not found");
    }

    function isPlayerInGame(address playerAddress) public view returns (bool) {
        for (uint i = 0; i < players.length; i++) {
            if (players[i].addr == playerAddress) {
                return true;
            }
        }
        return false;
    }

    function getActivePlayerCount() private view returns (uint256) {
        uint256 count = 0;
        for (uint i = 0; i < players.length; i++) {
            if (players[i].isActive) {
                count++;
            }
        }
        return count;
    }

    function endRound() private {
        // For now, just reset the game state
        currentGame.phase = GamePhase.Joining;
        delete players;
        currentGame.pot = 0;
        currentGame.currentBet = 0;
        currentGame.lastBetAmount = 0;
        currentGame.currentCardIndex = 0;
        currentGame.communityCardsDealt = 0;
        for(uint8 i = 0; i < 5; i++) {
            currentGame.communityCards[i] = 0;
        }
    }

    function areBetsEqual() private view returns (bool) {
        uint256 firstBet = bets[players[0].addr];
        uint256 secondBet = bets[players[1].addr];
        return firstBet == secondBet;
    }

    function moveToNextPhase() private {
        if (currentGame.phase == GamePhase.PreFlopBetting) {
            currentGame.phase = GamePhase.FlopDealing;
        } else if (currentGame.phase == GamePhase.FlopBetting) {
            currentGame.phase = GamePhase.TurnDealing;
        } else if (currentGame.phase == GamePhase.TurnBetting) {
            currentGame.phase = GamePhase.RiverDealing;
        } else if (currentGame.phase == GamePhase.RiverBetting) {
            currentGame.phase = GamePhase.ShowDown;
        }
        currentGame.currentBet = 0;
        currentGame.lastBetAmount = 0;
    }
}