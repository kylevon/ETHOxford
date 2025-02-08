import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web3dart/web3dart.dart';
import 'contract_interface.dart';
import 'config.dart';
import 'dart:async';
import 'dart:math';

class CardDeckWidget extends StatefulWidget {
  final Function(List<int>) onSubmit;
  final bool isEnabled;

  const CardDeckWidget({
    super.key,
    required this.onSubmit,
    this.isEnabled = true,
  });

  @override
  State<CardDeckWidget> createState() => _CardDeckWidgetState();
}

class _CardDeckWidgetState extends State<CardDeckWidget> {
  List<int> deck = List.generate(52, (i) => i);
  List<int> encryptedDeck = [];
  bool isEncrypted = false;

  String getCardString(int cardIndex) {
    final suits = ['♠', '♣', '♥', '♦'];
    final values = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
    
    final suit = suits[cardIndex ~/ 13];
    final value = values[cardIndex % 13];
    
    return '$value$suit';
  }

  Color getCardColor(int cardIndex) {
    return cardIndex ~/ 13 >= 2 ? Colors.red : Colors.black;
  }

  void shuffleDeck() {
    if (!isEncrypted) {
      setState(() {
        deck.shuffle(Random.secure());
      });
    }
  }

  void encryptDeck() {
    if (!isEncrypted) {
      setState(() {
        // For now, we'll just use the current permutation as the "encryption"
        // In a real implementation, you'd want to actually encrypt the values
        encryptedDeck = List.from(deck);
        isEncrypted = true;
      });
    }
  }

  void submitDeck() {
    if (isEncrypted) {
      widget.onSubmit(encryptedDeck);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Card Deck',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 13,
                childAspectRatio: 0.7,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: 52,
              itemBuilder: (context, index) {
                final cardIndex = deck[index];
                return Card(
                  color: isEncrypted ? Colors.blue : Colors.white,
                  child: Center(
                    child: Text(
                      isEncrypted ? '🔒' : getCardString(cardIndex),
                      style: TextStyle(
                        color: getCardColor(cardIndex),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: widget.isEnabled && !isEncrypted ? shuffleDeck : null,
                child: const Text('Shuffle'),
              ),
              ElevatedButton(
                onPressed: widget.isEnabled && !isEncrypted ? encryptDeck : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                ),
                child: const Text('Encrypt'),
              ),
              ElevatedButton(
                onPressed: widget.isEnabled && isEncrypted ? submitDeck : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
                child: const Text('Submit'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
  String _phaseText = 'Not in game';
  int? _currentGameId;
  int? _playerGameId;
  bool _isMyTurn = false;

  @override
  void initState() {
    super.initState();
    _startStateCheck();
  }

  @override
  void dispose() {
    _stateCheckTimer?.cancel();
    _privateKeyController.dispose();
    super.dispose();
  }

  void _startStateCheck() {
    _stateCheckTimer?.cancel();
    _stateCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_isConnected || !mounted) return;

      try {
        // Cache previous values for comparison
        final prevIsInGame = _isInGame;
        final prevPhase = _currentPhase;
        final prevGameId = _currentGameId;
        
        // Only check game ID if not in game
        if (!_isInGame) {
          final gameId = await _contractInterface.getCurrentGameId();
          if (gameId != prevGameId) {
            setState(() {
              _currentGameId = gameId;
            });
          }
        }
        
        // Check if player is in game
        final isInGame = await _contractInterface.isPlayerInGame(_contractInterface.currentAccount!);
        if (isInGame != prevIsInGame) {
          setState(() {
            _isInGame = isInGame;
            if (!isInGame) {
              _phaseText = 'Not in game';
            }
          });
        }
        
        // Only get game state if in game
        if (_isInGame) {
          final gameState = await _contractInterface.getGameState();
          if (mounted && gameState != null) {
            final newPhase = gameState['phase'] as int;
            final firstPlayer = gameState['firstPlayer'] as EthereumAddress;
            final newIsFirstPlayer = firstPlayer.hex.toLowerCase() == 
                _contractInterface.currentAccount!.toLowerCase();
            final currentPlayer = gameState['currentPlayer'] as int;
            final isMyTurn = (currentPlayer == 0 && newIsFirstPlayer) || 
                           (currentPlayer == 1 && !newIsFirstPlayer);
                
            // Only update state if something changed
            if (newPhase != _currentPhase || newIsFirstPlayer != _isFirstPlayer || isMyTurn != _isMyTurn) {
              final phaseText = await _contractInterface.getPhaseText(newPhase);
              if (mounted) {
                setState(() {
                  _currentPhase = newPhase;
                  _isFirstPlayer = newIsFirstPlayer;
                  _phaseText = phaseText;
                  _isMyTurn = isMyTurn;
                });
              }
            }
          }
        }
      } catch (e) {
        print('Error updating game state: $e');
        if (mounted) {
          setState(() {
            _errorMessage = e.toString();
          });
        }
      }
    });
  }

  Widget _buildActionButton() {
    if (!_isConnected || !_isInGame) return const SizedBox.shrink();

    // For the encryption phase, show the card deck widget
    if (_currentPhase == 1 && _isFirstPlayer) {
      return Container(
        padding: const EdgeInsets.all(16.0),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: CardDeckWidget(
          onSubmit: (encryptedDeck) async {
            try {
              setState(() => _isLoading = true);
              await _contractInterface.submitEncryptedDeck(encryptedDeck);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Successfully submitted encrypted deck!')),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
            } finally {
              if (mounted) {
                setState(() => _isLoading = false);
              }
            }
          },
        ),
      );
    }

    // Check if it's my turn based on the phase and player role
    bool shouldShowButton = false;
    String buttonText = '';

    switch (_currentPhase) {
      case 0: // Joining
        shouldShowButton = false;
        break;
      case 2: // SecondPlayerCardSelection
        shouldShowButton = !_isFirstPlayer;
        buttonText = 'Select Cards';
        break;
      case 3: // FirstPlayerDecryption
        shouldShowButton = _isFirstPlayer;
        buttonText = 'Decrypt Cards';
        break;
      case 4: // SecondPlayerCardEncryption
        shouldShowButton = !_isFirstPlayer;
        buttonText = 'Encrypt Cards';
        break;
      case 5: // FirstPlayerCardDecryption
        shouldShowButton = _isFirstPlayer;
        buttonText = 'Decrypt Own Cards';
        break;
      case 6: // SecondPlayerOwnCardSelection
        shouldShowButton = !_isFirstPlayer;
        buttonText = 'Select Own Cards';
        break;
      case 7: // SecondPlayerDeckSort
        shouldShowButton = !_isFirstPlayer;
        buttonText = 'Submit Sorted Deck';
        break;
      case 8: // DeckEncryption
        shouldShowButton = !_isFirstPlayer;
        buttonText = 'Submit Final Encryption';
        break;
      case 9: // PreFlopBetting
      case 11: // FlopBetting
      case 13: // TurnBetting
      case 15: // RiverBetting
        shouldShowButton = _isMyTurn;
        buttonText = 'Place Bet';
        break;
      case 10: // FlopDealing
      case 12: // TurnDealing
      case 14: // RiverDealing
        shouldShowButton = _isFirstPlayer;
        buttonText = 'Deal Cards';
        break;
      default:
        shouldShowButton = false;
    }

    if (!shouldShowButton) return const SizedBox.shrink();

    return Column(
      children: [
        ElevatedButton(
          onPressed: _handlePhaseAction,
          child: Text(buttonText),
        ),
        if (_isBettingPhase(_currentPhase))
          ElevatedButton(
            onPressed: () => _handleFold(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Fold'),
          ),
      ],
    );
  }

  bool _isBettingPhase(int phase) {
    return phase == 9 || phase == 11 || phase == 13 || phase == 15;
  }

  Future<void> _handleFold() async {
    try {
      setState(() {
        _isLoading = true;
      });
      await _contractInterface.fold();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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
            // Generate a random deck of 52 cards
            final random = Random.secure();
            final encryptedDeck = List<int>.generate(52, (i) => i)..shuffle(random);
            print('Generated encrypted deck: $encryptedDeck');
            try {
              await _contractInterface.submitEncryptedDeck(encryptedDeck);
              print('Successfully submitted encrypted deck');
            } catch (e) {
              print('Error submitting encrypted deck: $e');
              rethrow;
            }
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
      
      // Force immediate state refresh after joining
      final gameState = await _contractInterface.getGameState();
      if (gameState != null) {
        final newPhase = gameState['phase'] as int;
        final firstPlayer = gameState['firstPlayer'] as EthereumAddress;
        final newIsFirstPlayer = firstPlayer.hex.toLowerCase() == 
            _contractInterface.currentAccount!.toLowerCase();
        final currentPlayer = gameState['currentPlayer'] as int;
        final isMyTurn = (currentPlayer == 0 && newIsFirstPlayer) || 
                       (currentPlayer == 1 && !newIsFirstPlayer);
        
        setState(() {
          _isInGame = true;
          _currentPhase = newPhase;
          _isFirstPlayer = newIsFirstPlayer;
          _isMyTurn = isMyTurn;
        });
        
        _contractInterface.getPhaseText(newPhase).then((text) {
          if (mounted) {
            setState(() {
              _phaseText = text;
            });
          }
        });
      }

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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                        Column(
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
                            if (_currentGameId != null)
                              Text('Current Game ID: $_currentGameId'),
                            Text('Phase: $_phaseText'),
                            if (_isInGame) ...[
                              Text('Role: ${_isFirstPlayer ? "First Player" : "Second Player"}'),
                              if (_isMyTurn)
                                const Text(
                                  'Your Turn!',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      if (!_isInGame)
                        ElevatedButton(
                          onPressed: _joinGame,
                          child: const Text('Join Game'),
                        ),
                      _buildActionButton(),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
} 