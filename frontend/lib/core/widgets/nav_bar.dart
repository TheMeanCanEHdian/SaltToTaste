import 'package:flutter/material.dart';

class NavBar extends StatelessWidget {
  final bool loading;

  const NavBar({
    Key? key,
    this.loading = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color.fromRGBO(145, 0, 6, 1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _NavBarLogo(),
              Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          '/settings',
                        );
                      },
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: const Center(
                          child: Text(
                            'Settings',
                            style: TextStyle(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 56,
                    child: Material(
                      color: Colors.transparent,
                      child: PopupMenuButton(
                        icon: const Icon(
                          Icons.more_vert,
                          color: Colors.white,
                        ),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            child: Text('Item 1'),
                          ),
                          const PopupMenuItem(
                            child: Text('Item 2'),
                          ),
                          const PopupMenuItem(
                            child: Text('Item 3'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (loading) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

class _NavBarLogo extends StatelessWidget {
  const _NavBarLogo({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(context, '/');
        },
        hoverColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: SizedBox(
            height: 40,
            child: Image.asset('assets/logo/logo-banner-40.png'),
          ),
        ),
      ),
    );
  }
}
