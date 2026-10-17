// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:arrow_escape/data/level_binary_codec.dart';
import 'package:arrow_escape/data/models/level.dart';
// Imported solver engine to validate mathematical clearing steps
import 'package:arrow_escape/data/level_generator/solver.dart';

/// Reads the existing baseline levels from assets/levels.bin,
/// filters out broken, circular, or overlapping maps using structural solvers,
/// dynamically appends the shifted layout loop for stages 501-600,
/// and saves the verified 600-stage asset pack back to assets/levels.bin.
///
/// Run from project root:
///   flutter test test/generate_levels_bin_test.dart -r expanded
void main() {
  test('Generate and encode all 600 levels to assets/levels.bin', () {
    print('──────────────────────────────────────────────');
    print(' Arrow Puzzle — Binary Level Pre-generator');
    print('──────────────────────────────────────────────');

    final levels = <LevelModel>[];
    final sw = Stopwatch()..start();

    final binPath = 'assets/levels.bin';
    final binFile = File(binPath);

    if (!binFile.existsSync()) {
      fail('Could not find baseline binary file at "$binPath". Please run your chunk generator or verification tests first to build the base 500 levels.');
    }

    print('Reading baseline levels from $binPath...');
    try {
      final inputBytes = binFile.readAsBytesSync();
      final decoder = LevelBinaryDecoder.fromBytes(inputBytes);
      
      // Extract the original 500 levels and verify solvability + vector loop paths
      for (int i = 1; i <= 500; i++) {
        final decodedLevel = decoder.decodeLevelByNumber(i);
        if (decodedLevel != null) {
          
          // --- 1. SCAN FOR SELF-LOOPING/CORRUPTED MULTI-DOT ARROWS ---
          bool hasSelfLoopingArrow = false;
          for (final arrow in decodedLevel.arrows) {
            if (arrow.path.length >= 3) {
              // Convert coordinate sets to clean string keys to verify unique node coverage
              final distinctPoints = arrow.path.map((p) => '${p[0]},${p[1]}').toSet();
              
              // If the unique set length is lower than the path array, it overlaps itself in a loop
              if (distinctPoints.length < arrow.path.length) {
                hasSelfLoopingArrow = true;
                break;
              }
            }
          }

          // --- 2. RUN GAME SOLVER GATEPASS VERIFICATION ---
          final solution = LevelSolver.solve(decodedLevel);
          
          // Force layout healing if the solver fails, an arrow self-loops, or it hits known defects (L9, L388)
          if (solution == null || hasSelfLoopingArrow || i == 9 || i == 388) {
            print('⚠️ WARNING: Level $i contains a corrupted/looping arrow or layout defect!');
            print('🔧 Healing Level $i automatically by re-mapping to a clean, verified structural layout...');
            
            // Choose a lower-tier verified tutorial template for Level 9, or a clean scale fallback for high levels
            final fallbackSolvableIndex = (i == 9) ? 4 : 1 + (i % 5);
            final healingTemplate = decoder.decodeLevelByNumber(fallbackSolvableIndex)!;
            
            final healedLevel = LevelModel(
              levelNumber: i,
              gridSize: healingTemplate.gridSize,
              patternName: 'Healed-L$fallbackSolvableIndex',
              arrows: healingTemplate.arrows.map((a) => a.copyWith()).toList(),
              difficulty: healingTemplate.difficulty,
            );
            
            levels.add(healedLevel);
          } else {
            // Level layout is completely safe and solvable, proceed normally
            levels.add(decodedLevel);
          }
          
        } else {
          print('  Warning: Could not decode level $i from binary asset.');
        }
      }
    } catch (e) {
      fail('Failed parsing original binary file content: $e');
    }

    print('Successfully extracted and verified ${levels.length} base levels from your binary asset.');

    // 2. Generate levels 501 to 600 using the Shifted Layout Loop Offset
    print('Generating shifted progression loop for levels 501-600...');
    for (int i = 501; i <= 600; i++) {
      // Safely map index 501-600 to validated patterns from levels 201-300
      final shiftedTargetIndex = 201 + ((i - 501) % 100);
      
      // Find the baseline template from our extracted list array
      final baseLevel = levels.firstWhere(
        (l) => l.levelNumber == shiftedTargetIndex,
        orElse: () => fail('Failed to find level $shiftedTargetIndex in the extracted binary data.'),
      );
      
      // Clone into a fresh progressive LevelModel instance
      final shiftedLevel = LevelModel(
        levelNumber: i,
        gridSize: baseLevel.gridSize,
        patternName: 'Shift-${baseLevel.patternName}',
        arrows: baseLevel.arrows.map((a) => a.copyWith()).toList(),
        difficulty: baseLevel.difficulty,
      );
      
      levels.add(shiftedLevel);
    }

    // Sort to verify absolute sequence continuity
    levels.sort((a, b) => a.levelNumber.compareTo(b.levelNumber));

    // Print a quick visual sampling check to the terminal
    print('\n--- Verification Sample Matrix Check ---');
    for (final lvl in levels.where((l) => l.levelNumber % 50 == 0 || l.levelNumber > 595)) {
      print('Level ${lvl.levelNumber.toString().padLeft(3)} '
            '[${lvl.patternName.padRight(12)}] '
            '${lvl.arrows.length.toString().padLeft(3)} arrows '
            '${lvl.gridSize}×${lvl.gridSize}');
    }

    sw.stop();
    print('');
    print('Generation complete: ${sw.elapsed.inSeconds}s for ${levels.length} total levels');

    // 3. Encode the updated 600 levels list directly back to binary format
    print('Encoding 600 levels back to binary...');
    final encodeSw = Stopwatch()..start();
    final outputBytes = encodeLevels(levels);
    encodeSw.stop();

    binFile.writeAsBytesSync(outputBytes);

    final kbSize = (outputBytes.length / 1024).toStringAsFixed(1);
    print('Written: $binPath (${kbSize} KB, ${outputBytes.length} bytes)');
    print('Encoding time: ${encodeSw.elapsedMilliseconds}ms');

    print('');
    print('Done! ✓');
  });
}
