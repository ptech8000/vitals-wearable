class UserProfile {
  final String name;
  final String email;
  final int age;

  UserProfile({required this.name, required this.email, required this.age});

  Map<String, dynamic> toJson() => {'name': name, 'email': email, 'age': age};

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      age: json['age'] ?? 0,
    );
  }
}
