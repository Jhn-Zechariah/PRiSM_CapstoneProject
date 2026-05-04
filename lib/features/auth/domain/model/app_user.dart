class AppUser{
  final String uid;
  final String username;
  final String email;


  AppUser({
  required this.uid,
  required this.username,
  required this.email
  });

  //convert app user --> jason
  Map<String, dynamic> toJson(){
    return{
      'uid':uid,
      'username':username,
      'email':email,
    };
  }

  //convert json to -> app user
factory AppUser.fromJson(Map<String, dynamic> jsonUser){
    return AppUser(
        uid: jsonUser['uid'],
      username: jsonUser['uid'],
        email: jsonUser['email'],
    );
}
}

