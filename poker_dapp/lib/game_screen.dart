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
  final TextEditingController _seedController = TextEditingController();
  List<int> usedSeeds = [];

  @override
  void dispose() {
    _seedController.dispose();
    super.dispose();
  }

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
      final seed = int.tryParse(_seedController.text);
      if (seed == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid number for encryption')),
        );
        return;
      }
      
      setState(() {
        // Identity encryption - just use the current deck order
        encryptedDeck = List.from(deck);
        isEncrypted = true;
        usedSeeds.add(seed);
        _seedController.clear();
      });
    }
  }

  void generateRandomSeed() {
    final random = Random.secure();
    final seed = random.nextInt(1000000); // Generate a random 6-digit number
    _seedController.text = seed.toString();
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
          Text(
            isEncrypted ? 'Encrypted Deck' : 'Card Deck',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (!isEncrypted) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _seedController,
                    decoration: const InputDecoration(
                      labelText: 'Encryption Key',
                      hintText: 'Enter a number for encryption',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: generateRandomSeed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                  ),
                  child: const Text('Generate Random Key'),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (usedSeeds.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Used Encryption Keys:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(usedSeeds.join(', ')),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
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
                  color: isEncrypted ? Colors.blue.shade100 : Colors.white,
                  child: Center(
                    child: isEncrypted 
                      ? const Icon(Icons.lock, color: Colors.blue)
                      : Text(
                          getCardString(cardIndex),
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

class CardSelectionWidget extends StatefulWidget {
  final Function(List<int>, List<int>, List<int>, int) onSubmit;
  final bool isEnabled;

  const CardSelectionWidget({
    super.key,
    required this.onSubmit,
    this.isEnabled = true,
  });

  @override
  State<CardSelectionWidget> createState() => _CardSelectionWidgetState();
}

class _CardSelectionWidgetState extends State<CardSelectionWidget> {
  List<int> firstPlayerCards = [];
  List<int> secondPlayerCards = [];
  List<int> flopCards = [];
  final TextEditingController _seedController = TextEditingController();
  bool isFirstPlayerCardsSelected = false;
  bool isSecondPlayerCardsSelected = false;
  bool isFlopCardsSelected = false;

  @override
  void dispose() {
    _seedController.dispose();
    super.dispose();
  }

  void selectCard(int index, String type) {
    setState(() {
      switch (type) {
        case 'first_player':
          if (firstPlayerCards.contains(index)) {
            firstPlayerCards.remove(index);
          } else if (firstPlayerCards.length < 2) {
            firstPlayerCards.add(index);
          }
          break;
        case 'second_player':
          if (secondPlayerCards.contains(index)) {
            secondPlayerCards.remove(index);
          } else if (secondPlayerCards.length < 2) {
            secondPlayerCards.add(index);
          }
          break;
        case 'flop':
          if (flopCards.contains(index)) {
            flopCards.remove(index);
          } else if (flopCards.length < 5) {
            flopCards.add(index);
          }
          break;
      }
    });
  }

  void generateRandomSeed() {
    final random = Random.secure();
    final seed = random.nextInt(1000000); // Generate a random 6-digit number
    _seedController.text = seed.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Select Cards',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _seedController,
                  decoration: const InputDecoration(
                    labelText: 'Encryption Seed',
                    hintText: 'Enter a number for encryption',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: generateRandomSeed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                ),
                child: const Text('Generate Random Seed'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // First Player Card Selection
          Column(
            children: [
              const Text(
                'Select 2 Cards for First Player (Unencrypted)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 13,
                    childAspectRatio: 0.7,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: 52,
                  itemBuilder: (context, index) {
                    final isSelected = firstPlayerCards.contains(index);
                    return GestureDetector(
                      onTap: widget.isEnabled ? () => selectCard(index, 'first_player') : null,
                      child: Card(
                        color: isSelected ? Colors.green.shade200 : Colors.white,
                        child: Center(
                          child: Text(
                            getCardString(index),
                            style: TextStyle(
                              color: getCardColor(index),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Second Player Card Selection
          Column(
            children: [
              const Text(
                'Select 2 Cards for Yourself (Will be Encrypted)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 13,
                    childAspectRatio: 0.7,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: 52,
                  itemBuilder: (context, index) {
                    final isSelected = secondPlayerCards.contains(index);
                    return GestureDetector(
                      onTap: widget.isEnabled ? () => selectCard(index, 'second_player') : null,
                      child: Card(
                        color: isSelected ? Colors.blue.shade200 : Colors.white,
                        child: Center(
                          child: Text(
                            getCardString(index),
                            style: TextStyle(
                              color: getCardColor(index),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Flop Card Selection
          Column(
            children: [
              const Text(
                'Select 5 Cards for Flop (Will be Encrypted)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 13,
                    childAspectRatio: 0.7,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: 52,
                  itemBuilder: (context, index) {
                    final isSelected = flopCards.contains(index);
                    return GestureDetector(
                      onTap: widget.isEnabled ? () => selectCard(index, 'flop') : null,
                      child: Card(
                        color: isSelected ? Colors.purple.shade200 : Colors.white,
                        child: Center(
                          child: Text(
                            getCardString(index),
                            style: TextStyle(
                              color: getCardColor(index),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Selected: ${firstPlayerCards.length}/2 first player, ${secondPlayerCards.length}/2 second player, ${flopCards.length}/5 flop',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: widget.isEnabled && 
                      firstPlayerCards.length == 2 && 
                      secondPlayerCards.length == 2 && 
                      flopCards.length == 5 &&
                      _seedController.text.isNotEmpty
                ? () {
                    final seed = int.parse(_seedController.text);
                    widget.onSubmit(firstPlayerCards, secondPlayerCards, flopCards, seed);
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text(
              'Submit Selected Cards',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

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

    // For second player card selection phase
    if (_currentPhase == 2 && !_isFirstPlayer) {
      return Container(
        padding: const EdgeInsets.all(16.0),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: CardSelectionWidget(
          onSubmit: (firstPlayerCards, secondPlayerCards, flopCards, seed) async {
            try {
              setState(() => _isLoading = true);
              await _contractInterface.selectCards(firstPlayerCards, secondPlayerCards, flopCards, seed);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cards selected successfully!')),
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
      case 3: // PreFlopBetting
      case 5: // FlopBetting
      case 7: // TurnBetting
      case 9: // RiverBetting
        shouldShowButton = _isMyTurn;
        buttonText = 'Place Bet';
        break;
      case 4: // FlopDealing
      case 6: // TurnDealing
      case 8: // RiverDealing
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
            await _contractInterface.submitEncryptedDeck(encryptedDeck);
          }
          break;
        case 2: // Second Player Card Selection
          if (!_isFirstPlayer) {
            // This will be handled by the CardSelectionWidget
            // The widget will call selectCards with the appropriate parameters
          }
          break;
        case 3: // PreFlopBetting
        case 5: // FlopBetting
        case 7: // TurnBetting
        case 9: // RiverBetting
          final betAmount = BigInt.from(100000000000000000); // 0.1 ETH
          await _contractInterface.placeBet(betAmount);
          break;
        case 4: // FlopDealing
        case 6: // TurnDealing
        case 8: // RiverDealing
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