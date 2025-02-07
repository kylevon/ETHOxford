import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_web3/flutter_web3.dart';
import 'contract_interface.dart';
import 'dart:math';

class GameScreen extends StatefulWidget {
  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late ContractInterface contractInterface;
  Map<String, dynamic> gameState = {};
  List<dynamic> playerInfo = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    contractInterface = ContractInterface();
    _initializeContract();
  }

  Future<void> _initializeContract() async {
    setState(() => isLoading = true);
    try {
      if (!Ethereum.isSupported) {
        throw Exception('Ethereum is not supported. Please install MetaMask.');
      }
      
      await contractInterface.initialize();
      await _refreshGameState();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _refreshGameState() async {
    try {
      if (!Ethereum.isSupported) {
        throw Exception('Ethereum is not supported. Please install MetaMask.');
      }

      final state = await contractInterface.getGameState();
      final address = await ethereum!.requestAccount();
      final player = await contractInterface.getPlayerInfo(address[0]);
      
      if (mounted) {
        setState(() {
          gameState = state;
          playerInfo = player;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error refreshing game state: $e')),
        );
      }
    }
  }

  Widget _buildGamePhaseInfo() {
    final phase = gameState['phase'] ?? 0;
    final phases = [
      'Joining', 'First Player Encryption', 'Second Player Card Selection',
      'First Player Decryption', 'Second Player Card Encryption',
      'First Player Card Decryption', 'Second Player Own Card Selection',
      'Second Player Deck Sort', 'Deck Encryption', 'Pre-Flop Betting',
      'Flop Dealing', 'Flop Betting', 'Turn Dealing', 'Turn Betting',
      'River Dealing', 'River Betting', 'ShowDown'
    ];

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Current Phase:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(phases[phase], style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerInfo() {
    if (playerInfo.isEmpty) {
      return ElevatedButton(
        onPressed: () => contractInterface.joinGame(BigInt.from(1e18)),
        child: Text('Join Game'),
      );
    }

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Your Cards:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildCard(playerInfo[3][0]),
                SizedBox(width: 8),
                _buildCard(playerInfo[3][1]),
              ],
            ),
            Text('Chips: ${playerInfo[1]}'),
            Text('Active: ${playerInfo[2]}'),
          ],
        ),
      ),
    );
  }

  Widget _buildCommunityCards() {
    final cards = gameState['communityCards'] as List<dynamic>? ?? [];
    final cardsDealt = gameState['communityCardsDealt'] as int? ?? 0;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Community Cards:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 5; i++)
                  if (i < cardsDealt) _buildCard(cards[i])
                  else _buildEmptyCard(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(int cardValue) {
    final suit = ['♠', '♣', '♥', '♦'][cardValue ~/ 13];
    final value = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'][cardValue % 13];
    final isRed = suit == '♥' || suit == '♦';

    return Container(
      width: 60,
      height: 90,
      margin: EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          '$value$suit',
          style: TextStyle(
            fontSize: 20,
            color: isRed ? Colors.red : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyCard() {
    return Container(
      width: 60,
      height: 90,
      margin: EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _buildActionButtons() {
    final phase = gameState['phase'] ?? 0;
    final isBettingPhase = [9, 11, 13, 15].contains(phase);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isBettingPhase) ...[
          ElevatedButton(
            onPressed: () => contractInterface.placeBet(BigInt.from(1e17)),
            child: Text('Bet 0.1 ETH'),
          ),
          SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => contractInterface.fold(),
            child: Text('Fold'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
        SizedBox(width: 8),
        ElevatedButton(
          onPressed: _refreshGameState,
          child: Text('Refresh'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Poker DApp'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildGamePhaseInfo(),
            SizedBox(height: 16),
            _buildPlayerInfo(),
            SizedBox(height: 16),
            _buildCommunityCards(),
            SizedBox(height: 16),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }
} 