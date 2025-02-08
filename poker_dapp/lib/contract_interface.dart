import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart';
import 'dart:convert';
import 'config.dart';

class ContractInterface {
  Web3Client? web3client;
  DeployedContract? contract;
  String? currentAccount;
  bool isInitialized = false;
  late Credentials credentials;

  ContractInterface();

  Future<void> initializeWithPrivateKey(String privateKey) async {
    try {
      // Initialize Web3
      final client = Client();
      web3client = Web3Client('http://127.0.0.1:8545', client);

      // Load contract ABI
      final abiString = await rootBundle.loadString('assets/PokerGame.json');
      print('Loaded ABI string: ${abiString.substring(0, 100)}...'); // Print first 100 chars
      
      final abiJson = jsonDecode(abiString);
      print('Parsed ABI JSON: ${jsonEncode(abiJson).substring(0, 100)}...'); // Print first 100 chars
      
      final abi = abiJson['abi'];
      if (abi == null) {
        throw Exception('Invalid contract ABI: ABI field not found in JSON.');
      }
      
      print('ABI functions:');
      final parsedAbi = ContractAbi.fromJson(jsonEncode(abi), 'PokerGame');
      for (var function in parsedAbi.functions) {
        print('- ${function.name}');
      }

      // Create contract instance
      contract = DeployedContract(
        parsedAbi,
        EthereumAddress.fromHex(Config.contractAddress),
      );

      // Get credentials from private key
      credentials = EthPrivateKey.fromHex(privateKey);
      currentAccount = (await credentials.extractAddress()).hex;
      print('Connected with account: $currentAccount');

      print('Contract initialized with address: ${Config.contractAddress}');
      isInitialized = true;

      // Test currentGameId call
      try {
        final gameIdFunction = contract!.function('currentGameId');
        print('Found currentGameId function: ${gameIdFunction.name}');
        final result = await web3client!.call(
          contract: contract!,
          function: gameIdFunction,
          params: [],
        );
        if (result.isNotEmpty) {
          final gameId = (result[0] as BigInt).toInt();
          print('Current game ID: $gameId');
        }
      } catch (e) {
        print('Error testing currentGameId: $e');
      }

      // Check if player is already in game
      final isInGame = await isPlayerInGame(currentAccount!);
      if (isInGame) {
        print('Player is already in the game');
      }
    } catch (e) {
      print('Contract initialization error: $e');
      throw Exception('Failed to initialize contract: $e');
    }
  }

  Future<bool> isPlayerInGame(String address) async {
    try {
      if (!isInitialized) {
        return false;
      }
      final function = contract!.function('isPlayerInGame');
      final result = await web3client!.call(
        contract: contract!,
        function: function,
        params: [EthereumAddress.fromHex(address)],
      );
      if (result.isEmpty) {
        return false;
      }
      return result[0] as bool;
    } catch (e) {
      print('Error checking if player is in game: $e');
      return false;
    }
  }

  Future<int> getCurrentGameId() async {
    try {
      if (!isInitialized) {
        throw Exception('Contract not initialized');
      }

      final function = contract!.function('currentGameId');
      print('Calling function: ${function.name}');
      final result = await web3client!.call(
        contract: contract!,
        function: function,
        params: [],
      );

      print('Raw result from contract call: $result');
      if (result.isEmpty) {
        print('No game ID returned');
        return 0;
      }

      final gameId = (result[0] as BigInt).toInt();
      print('Current game ID: $gameId');
      return gameId;
    } catch (e) {
      print('Error getting current game ID: $e');
      throw Exception('Failed to get current game ID: $e');
    }
  }

  Future<int> getPlayerGameId(String address) async {
    try {
      final function = contract!.function('getPlayerGameId');
      final result = await web3client!.call(
        contract: contract!,
        function: function,
        params: [EthereumAddress.fromHex(address)],
      );
      return (result[0] as BigInt).toInt();
    } catch (e) {
      print('Error getting player game ID: $e');
      return 0;
    }
  }

  Future<bool> createNewGame() async {
    if (!isInitialized) {
      throw Exception('Contract not initialized. Please connect wallet first.');
    }

    try {
      print('Creating new game...');
      final function = contract!.function('createNewGame');
      final transaction = await web3client!.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: contract!,
          function: function,
          parameters: [],
        ),
        chainId: 31337,
      );
      
      // Wait for transaction to be mined
      print('Waiting for transaction receipt...');
      TransactionReceipt? receipt;
      do {
        receipt = await web3client!.getTransactionReceipt(transaction);
        if (receipt == null) {
          await Future.delayed(const Duration(seconds: 1));
        }
      } while (receipt == null);
      
      print('Transaction successful, hash: ${receipt.transactionHash}');
      
      // Wait a bit for the state to update
      await Future.delayed(const Duration(seconds: 2));
      
      // Verify game was created by checking new game ID
      final newGameId = await getCurrentGameId();
      if (newGameId == 0) {
        throw Exception('Failed to create game - no game ID returned');
      }
      
      print('Successfully created new game with ID: $newGameId');
      return true;
    } catch (e) {
      print('Error creating game: $e');
      throw Exception('Failed to create game: $e');
    }
  }

  Future<bool> joinGame(BigInt buyInAmount) async {
    if (!isInitialized) {
      throw Exception('Contract not initialized. Please connect wallet first.');
    }

    try {
      // Check if player is already in game
      final isInGame = await isPlayerInGame(currentAccount!);
      print('Is player already in game? $isInGame');
      
      if (isInGame) {
        throw Exception('Already in game');
      }

      // Get current game ID
      var gameId = await getCurrentGameId();
      print('Current game ID before join: $gameId');
      
      // Get game state to check number of players
      final function = contract!.function('games');
      final result = await web3client!.call(
        contract: contract!,
        function: function,
        params: [BigInt.from(gameId)],
      );
      
      print('Raw game state before joining: $result');
      
      // Check if the game exists and is in joining phase
      if (result.isEmpty) {
        throw Exception('Game not found');
      }
      
      final phase = result[5] is BigInt ? (result[5] as BigInt).toInt() : 0;
      if (phase != 0) { // 0 = Joining phase
        throw Exception('Game is not in joining phase');
      }
      
      print('Joining game with ID: $gameId');
      print('Buy-in amount: $buyInAmount');
      print('Current account: $currentAccount');

      final joinFunction = contract!.function('joinGame');
      final transaction = await web3client!.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: contract!,
          function: joinFunction,
          parameters: [BigInt.from(gameId)],
          value: EtherAmount.fromBigInt(EtherUnit.wei, buyInAmount),
        ),
        chainId: 31337,
      );
      
      // Wait for transaction to be mined
      print('Waiting for join game transaction receipt...');
      TransactionReceipt? receipt;
      do {
        receipt = await web3client!.getTransactionReceipt(transaction);
        if (receipt == null) {
          await Future.delayed(const Duration(seconds: 1));
        }
      } while (receipt == null);
      
      print('Successfully joined game with transaction hash: ${receipt.transactionHash}');
      
      // Check game state after joining
      await Future.delayed(const Duration(seconds: 2)); // Wait for state to update
      final gameState = await getGameState();
      print('Game state after joining:');
      print('- Phase: ${await getPhaseText(gameState['phase'] as int)}');
      print('- First Player: ${gameState['firstPlayer']}');
      print('- Current Player: ${gameState['currentPlayer']}');
      print('- Number of players: ${(gameState['players'] as List?)?.length ?? 0}');
      
      return true;
    } catch (e) {
      print('Error joining game: $e');
      throw Exception('Failed to join game: $e');
    }
  }

  Future<bool> submitEncryptedDeck(List<int> encryptedDeck) async {
    try {
      final gameId = await getPlayerGameId(currentAccount!);
      final function = contract!.function('submitEncryptedDeck');
      final result = await web3client!.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: contract!,
          function: function,
          parameters: [BigInt.from(gameId), encryptedDeck],
        ),
        chainId: 31337,
      );
      return true;
    } catch (e) {
      print('Error submitting encrypted deck: $e');
      return false;
    }
  }

  Future<bool> selectCards(List<int> selectedIndices) async {
    try {
      final function = contract!.function('selectCards');
      final result = await web3client!.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: contract!,
          function: function,
          parameters: [selectedIndices],
        ),
        chainId: 31337,
      );
      return true;
    } catch (e) {
      print('Error selecting cards: $e');
      return false;
    }
  }

  Future<bool> decryptCards(List<int> decryptedCards, String forPlayer) async {
    try {
      final function = contract!.function('decryptCards');
      final result = await web3client!.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: contract!,
          function: function,
          parameters: [decryptedCards, EthereumAddress.fromHex(forPlayer)],
        ),
        chainId: 31337,
      );
      return true;
    } catch (e) {
      print('Error decrypting cards: $e');
      return false;
    }
  }

  Future<bool> selectOwnCards(List<int> selectedIndices) async {
    try {
      final function = contract!.function('selectOwnCards');
      final result = await web3client!.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: contract!,
          function: function,
          parameters: [selectedIndices],
        ),
        chainId: 31337,
      );
      return true;
    } catch (e) {
      print('Error selecting own cards: $e');
      return false;
    }
  }

  Future<bool> submitSortedDeck(List<int> sortedDeck) async {
    try {
      final function = contract!.function('submitSortedDeck');
      final result = await web3client!.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: contract!,
          function: function,
          parameters: [sortedDeck],
        ),
        chainId: 31337,
      );
      return true;
    } catch (e) {
      print('Error submitting sorted deck: $e');
      return false;
    }
  }

  Future<bool> dealCommunityCards() async {
    try {
      final function = contract!.function('dealCommunityCards');
      final result = await web3client!.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: contract!,
          function: function,
          parameters: [],
        ),
        chainId: 31337,
      );
      return true;
    } catch (e) {
      print('Error dealing community cards: $e');
      return false;
    }
  }

  Future<bool> placeBet(BigInt betAmount) async {
    try {
      final function = contract!.function('placeBet');
      final result = await web3client!.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: contract!,
          function: function,
          parameters: [],
          value: EtherAmount.fromBigInt(EtherUnit.wei, betAmount),
        ),
        chainId: 31337,
      );
      return true;
    } catch (e) {
      print('Error placing bet: $e');
      return false;
    }
  }

  Future<bool> fold() async {
    try {
      final function = contract!.function('fold');
      final result = await web3client!.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: contract!,
          function: function,
          parameters: [],
        ),
        chainId: 31337,
      );
      return true;
    } catch (e) {
      print('Error folding: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> getGameState() async {
    try {
      if (!isInitialized) {
        throw Exception('Contract not initialized');
      }
      
      final gameId = await getPlayerGameId(currentAccount!);
      print('Getting game state for game ID: $gameId');
      
      final function = contract!.function('games');
      final result = await web3client!.call(
        contract: contract!,
        function: function,
        params: [BigInt.from(gameId)],
      );

      print('Raw game state result: $result');

      if (result.isEmpty) {
        throw Exception('No game state found');
      }

      // The result array matches the struct fields in order
      final gameState = {
        'communityCards': result[0] is List ? result[0] as List : [],
        'pot': result[1] is BigInt ? result[1] as BigInt : BigInt.zero,
        'currentBet': result[2] is BigInt ? result[2] as BigInt : BigInt.zero,
        'currentPlayer': result[3] is BigInt ? (result[3] as BigInt).toInt() : 0,
        'roundDeadline': result[4] is BigInt ? result[4] as BigInt : BigInt.zero,
        'phase': result[5] is BigInt ? (result[5] as BigInt).toInt() : 0,
        'firstPlayer': result[6] is EthereumAddress ? result[6] as EthereumAddress : null,
        'lastBetAmount': result[7] is BigInt ? result[7] as BigInt : BigInt.zero,
        'communityCardsDealt': result[8] is BigInt ? (result[8] as BigInt).toInt() : 0,
      };

      print('Parsed game state:');
      print('- Phase: ${await getPhaseText(gameState['phase'] as int)}');
      if (gameState['firstPlayer'] != null) {
        print('- First player: ${gameState['firstPlayer']}');
      }
      print('- Current player: ${gameState['currentPlayer']}');
      
      return gameState;
    } catch (e) {
      print('Error getting game state: $e');
      return {
        'phase': 0,
        'pot': BigInt.zero,
        'currentBet': BigInt.zero,
        'currentPlayer': 0,
        'communityCards': [],
        'firstPlayer': null,
        'lastBetAmount': BigInt.zero,
        'communityCardsDealt': 0,
      };
    }
  }

  Future<List<dynamic>> getPlayerInfo(String address) async {
    try {
      final function = contract!.function('players');
      final result = await web3client!.call(
        contract: contract!,
        function: function,
        params: [],
      );
      
      for (var player in result) {
        if (player[0].toString().toLowerCase() == address.toLowerCase()) {
          return player;
        }
      }
      return [];
    } catch (e) {
      print('Error getting player info: $e');
      return [];
    }
  }

  Future<int> getCurrentPhase() async {
    try {
      final gameState = await getGameState();
      return gameState['phase'] as int;
    } catch (e) {
      print('Error getting current phase: $e');
      return 0; // Return Joining phase as default
    }
  }

  Future<bool> isFirstPlayer() async {
    try {
      final gameState = await getGameState();
      final firstPlayer = gameState['firstPlayer'];
      
      if (firstPlayer == null) return false;
      
      final isFirst = (firstPlayer as EthereumAddress).hex.toLowerCase() == currentAccount!.toLowerCase();
      print('Is first player check: ${firstPlayer.hex} vs $currentAccount = $isFirst');
      return isFirst;
    } catch (e) {
      print('Error checking if first player: $e');
      return false;
    }
  }

  Future<String> getPhaseText(int phase) async {
    switch (phase) {
      case 0:
        return 'Joining';
      case 1:
        return 'First Player Encryption';
      case 2:
        return 'Second Player Card Selection';
      case 3:
        return 'First Player Decryption';
      case 4:
        return 'Second Player Card Encryption';
      case 5:
        return 'First Player Card Decryption';
      case 6:
        return 'Second Player Own Card Selection';
      case 7:
        return 'Second Player Deck Sort';
      case 8:
        return 'Deck Encryption';
      case 9:
        return 'Pre-Flop Betting';
      case 10:
        return 'Flop Dealing';
      case 11:
        return 'Flop Betting';
      case 12:
        return 'Turn Dealing';
      case 13:
        return 'Turn Betting';
      case 14:
        return 'River Dealing';
      case 15:
        return 'River Betting';
      case 16:
        return 'Showdown';
      default:
        return 'Unknown Phase';
    }
  }
} 