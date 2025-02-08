import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web3dart/web3dart.dart';
import 'contract_interface.dart';
import 'config.dart';
import 'dart:async';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final ContractInterface _contractInterface = ContractInterface();
  final TextEditingController _privateKeyController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String? _connectedAddress;
  bool _isConnected = false;
  bool _isInGame = false;
  int _currentPhase = 0;
  bool _isFirstPlayer = false;
  Timer? _stateCheckTimer;
  String? _phaseText;

  @override
  void initState() {
    super.initState();
    _startStateCheck();
  }

  @override
  void dispose() {
    _privateKeyController.dispose();
    _stateCheckTimer?.cancel();
    super.dispose();
  }

  void _startStateCheck() {
    _stateCheckTimer?.cancel();
    _stateCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_isConnected && mounted) {
        try {
          final isInGame = await _contractInterface.isPlayerInGame(_contractInterface.currentAccount!);
          if (isInGame != _isInGame) {
            setState(() {
              _isInGame = isInGame;
            });
          }
          
          if (_isInGame) {
            final gameState = await _contractInterface.getGameState();
            if (mounted) {
              final phaseText = await _contractInterface.getPhaseText(gameState['phase'] as int);
              setState(() {
                _currentPhase = gameState['phase'] as int;
                _phaseText = phaseText;
                if (gameState['firstPlayer'] != null) {
                  _isFirstPlayer = gameState['firstPlayer'].toString().toLowerCase() == 
                      _contractInterface.currentAccount!.toLowerCase();
                }
              });
            }
          } else {
            setState(() {
              _phaseText = 'Not in game';
            });
          }
        } catch (e) {
          print('Error updating game state: $e');
        }
      }
    });
  }

  Future<void> _handlePhaseAction() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      switch (_currentPhase) {
        case 1: // First Player Encryption
          if (_isFirstPlayer) {
            // TODO: Implement proper encryption
            final encryptedDeck = List<int>.generate(52, (i) => i);
            await _contractInterface.submitEncryptedDeck(encryptedDeck);
          }
          break;
        case 2: // Second Player Card Selection
          if (!_isFirstPlayer) {
            // TODO: Implement proper card selection
            final selectedCards = [0, 1];
            await _contractInterface.selectCards(selectedCards);
          }
          break;
        case 3: // First Player Decryption
          if (_isFirstPlayer) {
            // TODO: Implement proper decryption
            final decryptedCards = [0, 1];
            await _contractInterface.decryptCards(decryptedCards, _contractInterface.currentAccount!);
          }
          break;
        case 4: // Second Player Card Encryption
          if (!_isFirstPlayer) {
            // TODO: Implement proper encryption
            final encryptedCards = [0, 1];
            await _contractInterface.submitEncryptedDeck(encryptedCards);
          }
          break;
        case 5: // First Player Card Decryption
          if (_isFirstPlayer) {
            // TODO: Implement proper decryption
            final decryptedCards = [0, 1];
            await _contractInterface.decryptCards(decryptedCards, _contractInterface.currentAccount!);
          }
          break;
        case 6: // Second Player Own Card Selection
          if (!_isFirstPlayer) {
            // TODO: Implement proper card selection
            final selectedCards = [0, 1];
            await _contractInterface.selectOwnCards(selectedCards);
          }
          break;
        case 7: // Second Player Deck Sort
          if (!_isFirstPlayer) {
            // TODO: Implement proper deck sorting
            final sortedDeck = List<int>.generate(52, (i) => i);
            await _contractInterface.submitSortedDeck(sortedDeck);
          }
          break;
        case 8: // Deck Encryption
          if (!_isFirstPlayer) {
            // TODO: Implement proper encryption
            final encryptedDeck = List<int>.generate(52, (i) => i);
            await _contractInterface.submitEncryptedDeck(encryptedDeck);
          }
          break;
        case 9: // Pre-Flop Betting
        case 11: // Flop Betting
        case 13: // Turn Betting
        case 15: // River Betting
          // TODO: Implement proper betting
          final betAmount = BigInt.from(100000000000000000); // 0.1 ETH
          await _contractInterface.placeBet(betAmount);
          break;
        case 10: // Flop Dealing
        case 12: // Turn Dealing
        case 14: // River Dealing
          if (_isFirstPlayer) {
            await _contractInterface.dealCommunityCards();
          }
          break;
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildGamePhaseUI() {
    if (!_isConnected || !_isInGame) return const SizedBox.shrink();

    return FutureBuilder<String>(
      future: _contractInterface.getPhaseText(_currentPhase),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();

        return Column(
          children: [
            const SizedBox(height: 16),
            Text(
              'Current Phase: ${snapshot.data}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_shouldShowActionButton())
              ElevatedButton(
                onPressed: _handlePhaseAction,
                child: Text(_getActionButtonText()),
              ),
          ],
        );
      },
    );
  }

  bool _shouldShowActionButton() {
    if (!_isConnected || !_isInGame) return false;
    
    switch (_currentPhase) {
      case 1: // First Player Encryption
        return _isFirstPlayer;
      case 2: // Second Player Card Selection
        return !_isFirstPlayer;
      case 3: // First Player Decryption
        return _isFirstPlayer;
      case 4: // Second Player Card Encryption
        return !_isFirstPlayer;
      case 5: // First Player Card Decryption
        return _isFirstPlayer;
      case 6: // Second Player Own Card Selection
        return !_isFirstPlayer;
      case 7: // Second Player Deck Sort
        return !_isFirstPlayer;
      case 8: // Deck Encryption
        return !_isFirstPlayer;
      case 9: // Pre-Flop Betting
      case 11: // Flop Betting
      case 13: // Turn Betting
      case 15: // River Betting
        return true; // Both players can bet
      case 10: // Flop Dealing
      case 12: // Turn Dealing
      case 14: // River Dealing
        return _isFirstPlayer;
      default:
        return false;
    }
  }

  String _getActionButtonText() {
    switch (_currentPhase) {
      case 1:
        return 'Submit Encrypted Deck';
      case 2:
        return 'Select Cards';
      case 3:
        return 'Decrypt Cards';
      case 4:
        return 'Encrypt Cards';
      case 5:
        return 'Decrypt Own Cards';
      case 6:
        return 'Select Own Cards';
      case 7:
        return 'Submit Sorted Deck';
      case 8:
        return 'Submit Final Encryption';
      case 9:
      case 11:
      case 13:
      case 15:
        return 'Place Bet';
      case 10:
      case 12:
      case 14:
        return 'Deal Cards';
      default:
        return 'Take Action';
    }
  }

  Future<void> _connectWallet() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final privateKey = _privateKeyController.text.trim();
      if (privateKey.isEmpty) {
        throw Exception('Please enter a private key');
      }
      
      if (!privateKey.startsWith('0x')) {
        throw Exception('Private key must start with 0x');
      }

      await _contractInterface.initializeWithPrivateKey(privateKey);
      final isInGame = await _contractInterface.isPlayerInGame(_contractInterface.currentAccount!);
      
      setState(() {
        _connectedAddress = _contractInterface.currentAccount;
        _isConnected = true;
        _isInGame = isInGame;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _joinGame() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final buyInAmount = BigInt.from(1000000000000000000); // 1 ETH
      await _contractInterface.joinGame(buyInAmount);
      setState(() {
        _isInGame = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Successfully joined the game!')),
      );
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Poker Game'),
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'Error: $_errorMessage',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    if (!_isConnected) ...[
                      const Text(
                        'Enter your private key to connect:',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _privateKeyController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Private Key',
                          hintText: '0x...',
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _connectWallet,
                        child: const Text('Connect Wallet'),
                      ),
                    ] else ...[
                      if (_connectedAddress != null)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              Text('Connected: $_connectedAddress'),
                              const SizedBox(height: 8),
                              Text(
                                _isInGame 
                                  ? 'Status: In game' 
                                  : 'Status: Not in game',
                                style: TextStyle(
                                  color: _isInGame ? Colors.green : Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (!_isInGame)
                        ElevatedButton(
                          onPressed: _joinGame,
                          child: const Text('Join Game'),
                        ),
                      _buildGamePhaseUI(),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
} 