import 'dart:math';

int generateSeed() {
  return Random().nextInt(pow(2, 31) as int);
}
