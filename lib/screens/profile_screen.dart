import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';
import 'stats_screen.dart';
import 'stats_graphs_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header customizado com logo
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F5F5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Botão voltar
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Color(0xFF23345F),
                      size: 24,
                    ),
                  ),
                  // Logo centralizado
                  Image.asset(
                    'assets/images/logo_socialx.png',
                    width: 120,             
                    fit: BoxFit.contain,
                  ),
                  // Ícone de perfil
                  const Icon(
                    Icons.person,
                    color: Color(0xFF8FAE5D),
                    size: 24,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  _buildProfileHeader(context),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildMenuItems(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

    // Definir valores padrão caso o usuário não esteja disponível
    final displayName = user?.fullName ?? 'Usuário';
    final displayRole = user?.role == 'aplicador'
        ? 'Aplicador de Campo'
        : (user?.role == 'admin' ? 'Administrador' : 'Usuário');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: const BoxDecoration(
        color: Color(0xFF8FAE5D),
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person,
              size: 36,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 15),
          Text(
            displayName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            displayRole,
            style: const TextStyle(
              fontSize: 14,
              color: Color.fromRGBO(255, 255, 255, 0.9),
            ),
          ),
          if (user != null) ...[
            const SizedBox(height: 5),
            Text(
              'ID: ${user.username}',
              style: const TextStyle(
                fontSize: 12,
                color: Color.fromRGBO(255, 255, 255, 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMenuItems(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildMenuItem(
            icon: Icons.bar_chart,
            title: 'Gráficos',
            subtitle: 'Estatísticas gráficas',
            onTap: () => _navigateToStatsGraphs(context),
          ),
          _buildMenuItem(
            icon: Icons.bar_chart,
            title: 'Estatísticas',
            subtitle: 'Formulários aplicados',
            onTap: () => _navigateToStats(context),
          ),
          _buildMenuItem(
            icon: Icons.location_on,
            title: 'Localizações',
            subtitle: 'Áreas de atuação',
            onTap: () => _showNotImplemented(context),
          ),
          _buildMenuItem(
            icon: Icons.security,
            title: 'Privacidade',
            subtitle: 'Configurações de dados',
            onTap: () => _showNotImplemented(context),
          ),
          _buildMenuItem(
            icon: Icons.exit_to_app,
            title: 'Sair',
            subtitle: 'Fazer logout',
            isLast: true,
            isDanger: true,
            onTap: () => _logout(context),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isLast = false,
    bool isDanger = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          border: isLast ? null : const Border(
            bottom: BorderSide(color: Color(0xFFF0F0F0)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDanger ? Colors.red : const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 18,
                color: isDanger ? Colors.white : Colors.grey.shade700,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDanger ? Colors.red : const Color(0xFF23345F),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  _navigateToStats(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const StatsScreen()),
    );
  }

  _navigateToStatsGraphs(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const StatsGraphsScreen()),
    );
  }

  _showNotImplemented(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Funcionalidade em desenvolvimento'),
      ),
    );
  }

  _logout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Logout'),
        content: const Text('Tem certeza que deseja sair do aplicativo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              final authProvider = Provider.of<AuthProvider>(context, listen: false);
              await authProvider.logout();

              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Sair', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}