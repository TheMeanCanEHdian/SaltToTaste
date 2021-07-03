import 'package:flutter/material.dart';

class NavBar extends StatefulWidget {
  NavBar({Key? key}) : super(key: key);

  @override
  _NavBarState createState() => _NavBarState();
}

class _NavBarState extends State<NavBar> {
  final Map<String, bool> _isHovering = {
    'login': false,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: const Color.fromRGBO(145, 0, 6, 1),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  height: 40,
                  child: Image.asset('assets/logo/logo-banner-40.png'),
                ),
                InkWell(
                  onHover: (value) {
                    setState(() {
                      _isHovering['login'] = value;
                    });
                  },
                  onTap: () {},
                  child: Text(
                    'Login',
                    style: TextStyle(
                      color: _isHovering['login']!
                          ? Colors.lightGreen
                          : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
