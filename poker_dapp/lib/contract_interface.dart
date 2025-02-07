import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web3/flutter_web3.dart';
import 'package:web3dart/web3dart.dart';
import 'dart:convert';
import 'config.dart';

class ContractInterface {
  late Contract contract;
  late String contractAddress;
  late Web3Provider provider;

  ContractInterface();

  Future<void> initialize() async {
    if (!Ethereum.isSupported) {
      throw Exception('Ethereum is not supported. Please install MetaMask.');
    }

    try {
      provider = Web3Provider(ethereum!);
      final accounts = await ethereum!.requestAccount();
      if (accounts.isEmpty) {
        throw Exception('No accounts found. Please connect your wallet.');
      }

      // Load contract ABI
      final abiString = await rootBundle.loadString('assets/PokerGame.json');
      final abiJson = jsonDecode(abiString);
      final abi = abiJson['abi'];

      if (abi == null) {
        throw Exception('Invalid contract ABI.');
      }

      contract = Contract(
        Config.contractAddress,
        Interface(jsonEncode(abi)),
        provider.getSigner(),
      );
    } catch (e) {
      throw Exception('Failed to initialize contract: $e');
    }
  }

  Future<bool> joinGame(BigInt buyInAmount) async {
    try {
      final tx = await contract.send(
        'joinGame',
        [],
        TransactionOverride(value: buyInAmount),
      );
      final receipt = await tx.wait();
      return receipt.status == 1;
    } catch (e) {
      print('Error joining game: $e');
      return false;
    }
  }

  Future<bool> submitEncryptedDeck(List<int> encryptedDeck) async {
    try {
      final tx = await contract.send('submitEncryptedDeck', [encryptedDeck]);
      final receipt = await tx.wait();
      return receipt.status == 1;
    } catch (e) {
      print('Error submitting encrypted deck: $e');
      return false;
    }
  }

  Future<bool> selectCards(List<int> selectedIndices) async {
    try {
      final tx = await contract.send('selectCards', [selectedIndices]);
      final receipt = await tx.wait();
      return receipt.status == 1;
    } catch (e) {
      print('Error selecting cards: $e');
      return false;
    }
  }

  Future<bool> decryptCards(List<int> decryptedCards, String forPlayer) async {
    try {
      final tx = await contract.send('decryptCards', [decryptedCards, forPlayer]);
      final receipt = await tx.wait();
      return receipt.status == 1;
    } catch (e) {
      print('Error decrypting cards: $e');
      return false;
    }
  }

  Future<bool> selectOwnCards(List<int> selectedIndices) async {
    try {
      final tx = await contract.send('selectOwnCards', [selectedIndices]);
      final receipt = await tx.wait();
      return receipt.status == 1;
    } catch (e) {
      print('Error selecting own cards: $e');
      return false;
    }
  }

  Future<bool> submitSortedDeck(List<int> sortedDeck) async {
    try {
      final tx = await contract.send('submitSortedDeck', [sortedDeck]);
      final receipt = await tx.wait();
      return receipt.status == 1;
    } catch (e) {
      print('Error submitting sorted deck: $e');
      return false;
    }
  }

  Future<bool> dealCommunityCards() async {
    try {
      final tx = await contract.send('dealCommunityCards', []);
      final receipt = await tx.wait();
      return receipt.status == 1;
    } catch (e) {
      print('Error dealing community cards: $e');
      return false;
    }
  }

  Future<bool> placeBet(BigInt betAmount) async {
    try {
      final tx = await contract.send(
        'placeBet',
        [],
        TransactionOverride(value: betAmount),
      );
      final receipt = await tx.wait();
      return receipt.status == 1;
    } catch (e) {
      print('Error placing bet: $e');
      return false;
    }
  }

  Future<bool> fold() async {
    try {
      final tx = await contract.send('fold', []);
      final receipt = await tx.wait();
      return receipt.status == 1;
    } catch (e) {
      print('Error folding: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> getGameState() async {
    try {
      final result = await contract.call<List>('currentGame', []);
      return {
        'phase': result[5],
        'pot': result[1],
        'currentBet': result[2],
        'currentPlayer': result[3],
        'communityCards': result[0],
        'communityCardsDealt': result[10],
      };
    } catch (e) {
      print('Error getting game state: $e');
      return {};
    }
  }

  Future<List<dynamic>> getPlayerInfo(String address) async {
    try {
      final players = await contract.call<List>('players', []);
      for (var player in players) {
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
} 