class Pet {
  final String id;
  final String name;
  final String breed;
  final int age;
  final String? profileImageUrl;

  Pet({
    required this.id,
    required this.name,
    required this.breed,
    required this.age,
    this.profileImageUrl,
  });
}
