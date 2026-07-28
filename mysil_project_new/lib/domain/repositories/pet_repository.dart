import '../entities/pet.dart';

abstract class PetRepository {
  Future<List<Pet>> getPets();
  Future<Pet?> addPet(Pet pet);
  Future<bool> updatePet(Pet pet);
  Future<bool> deletePet(String id);
}
