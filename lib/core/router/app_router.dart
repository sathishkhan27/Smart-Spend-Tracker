import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../utils/date_range.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/presentation/verify_email_screen.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/dashboard/presentation/home_shell.dart';
import '../../features/insights/presentation/insights_screen.dart';
import '../../features/cards/presentation/card_detail_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/onboarding/presentation/data_access_screen.dart';
import '../../features/onboarding/presentation/email_connect_screen.dart';
import '../../features/onboarding/presentation/initial_sync_screen.dart';
import '../../features/onboarding/presentation/profile_setup_screen.dart';
import '../../features/onboarding/presentation/sms_connect_screen.dart';
import '../../features/profile/presentation/connected_sources_screen.dart';
import '../../features/profile/presentation/notification_settings_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/workspace_screen.dart';
import '../../features/transactions/presentation/add_transaction_screen.dart';
import '../../features/transactions/presentation/transaction_detail_screen.dart';
import '../../features/transactions/presentation/transactions_screen.dart';
import '../../features/upcoming/domain/recurring_expense.dart';
import '../../features/upcoming/presentation/recurring_edit_screen.dart';
import '../../features/upcoming/presentation/upcoming_screen.dart';
import '../../features/budget/presentation/budget_screen.dart';
import '../di/providers.dart';
import '../utils/formatters.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const welcome = '/welcome';
  static const login = '/login';
  static const register = '/register';
  static const verifyEmail = '/verify-email';
  static const setupProfile = '/setup/profile';
  static const setupAccess = '/setup/access';
  static const setupSms = '/setup/sms';
  static const setupEmail = '/setup/email';
  static const setupSync = '/setup/sync';
  static const home = '/home';
  static const transactions = '/transactions';
  static const insights = '/insights';
  static const upcoming = '/upcoming';
  static const profile = '/profile';
  static const notifications = '/notifications';
  static String transaction(String id) => '/transactions/view/$id';
  static String card(String id) => '/cards/$id';

  /// Activity list pre-filtered to a category (and period). The `nav` stamp
  /// makes a repeat tap re-apply the filter even if the URL is otherwise equal.
  static String transactionsFor({
    String? categoryId,
    String? paymentMode,
    String? bankName,
    String? counterparty,
    String? search,
    bool outflowOnly = false,
    bool inflowOnly = false,
    DateRangePeriod? period,
  }) =>
      Uri(path: transactions, queryParameters: {
        'category': ?categoryId,
        'mode': ?paymentMode,
        'bank': ?bankName,
        'payee': ?counterparty,
        'q': ?search,
        if (outflowOnly) 'dir': 'outflow',
        if (inflowOnly) 'dir': 'inflow',
        ...?period?.toQuery(),
        'nav': '${DateTime.now().millisecondsSinceEpoch}',
      }).toString();
  static const addTransaction = '/transactions/new';
  static const recurringEdit = '/upcoming/edit';
  static const workspace = '/profile/workspace';
  static const notificationSettings = '/profile/notifications';
  static const sources = '/profile/sources';
  static const budget = '/profile/budget';

  /// Budget page for one month (yyyy-MM in the query).
  static String budgetFor(DateRangePeriod month) => Uri(path: budget, queryParameters: {'month': Fmt.monthKey(month.start)}).toString();
}

/// Root navigator, for dialogs shown from app-level code (above the pages).
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Opens a route from a notification, banner or deep link.
///
/// Bottom-tab pages (and filtered variants like `/transactions?category=…`)
/// live inside the tab shell, so they are switched to with `go`. Pushing them
/// on top would put a second copy of the same page key in the navigator
/// ("!keyReservation.contains(key)" assertion). Other pages are pushed so Back
/// returns to where the user was.
void openAppRoute(GoRouter router, String route) {
  if (isTabRoute(route)) {
    router.go(route);
  } else {
    router.push(route);
  }
}

bool isTabRoute(String route) {
  final path = Uri.tryParse(route)?.path ?? route;
  return const {Routes.home, Routes.transactions, Routes.insights, Routes.upcoming, Routes.profile}.contains(path);
}

/// Rebuilds router redirects whenever session state changes.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(profileProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final auth = ref.read(authStateProvider);
      if (auth.isLoading) return loc == Routes.splash ? null : Routes.splash;

      final user = auth.value;
      const publicRoutes = {Routes.welcome, Routes.login, Routes.register};
      if (user == null) return publicRoutes.contains(loc) ? null : Routes.welcome;
      if (!user.emailVerified) return loc == Routes.verifyEmail ? null : Routes.verifyEmail;

      final profile = ref.read(profileProvider);
      if (profile.value == null) return loc == Routes.splash ? null : Routes.splash;
      final p = profile.value!;

      final inSetup = loc.startsWith('/setup');
      if (!p.onboardingComplete) return inSetup ? null : Routes.setupProfile;
      if (publicRoutes.contains(loc) || loc == Routes.splash || loc == Routes.verifyEmail) return Routes.home;
      if (inSetup && loc != Routes.setupSync && loc != Routes.setupSms && loc != Routes.setupEmail) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(path: Routes.welcome, builder: (_, __) => const WelcomeScreen()),
      GoRoute(path: Routes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(path: Routes.register, builder: (_, __) => const RegisterScreen()),
      GoRoute(path: Routes.verifyEmail, builder: (_, __) => const VerifyEmailScreen()),
      GoRoute(path: Routes.setupProfile, builder: (_, __) => const ProfileSetupScreen()),
      GoRoute(path: Routes.setupAccess, builder: (_, __) => const DataAccessScreen()),
      GoRoute(
        path: Routes.setupSms,
        builder: (_, s) => SmsConnectScreen(fromSettings: s.uri.queryParameters['settings'] == '1'),
      ),
      GoRoute(
        path: Routes.setupEmail,
        builder: (_, s) => EmailConnectScreen(fromSettings: s.uri.queryParameters['settings'] == '1'),
      ),
      GoRoute(path: Routes.setupSync, builder: (_, __) => const InitialSyncScreen()),
      GoRoute(path: Routes.notifications, builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/cards/:id', builder: (_, s) => CardDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(path: Routes.addTransaction, builder: (_, __) => const AddTransactionScreen()),
      GoRoute(path: '/transactions/view/:id', builder: (_, s) => TransactionDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(path: Routes.recurringEdit, builder: (_, s) => RecurringEditScreen(existing: s.extra as RecurringExpense?)),
      GoRoute(path: Routes.workspace, builder: (_, __) => const WorkspaceScreen()),
      GoRoute(path: Routes.notificationSettings, builder: (_, __) => const NotificationSettingsScreen()),
      GoRoute(path: Routes.sources, builder: (_, __) => const ConnectedSourcesScreen()),
      GoRoute(path: Routes.budget, builder: (_, s) => BudgetScreen(month: BudgetScreen.parseMonth(s.uri.queryParameters['month']))),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.home, builder: (_, __) => const DashboardScreen())]),
          StatefulShellBranch(routes: [GoRoute(
            path: Routes.transactions,
            builder: (_, s) => TransactionsScreen(
              categoryId: s.uri.queryParameters['category'],
              paymentMode: s.uri.queryParameters['mode'],
              bankName: s.uri.queryParameters['bank'],
              counterparty: s.uri.queryParameters['payee'],
              search: s.uri.queryParameters['q'],
              outflowOnly: s.uri.queryParameters['dir'] == 'outflow',
              inflowOnly: s.uri.queryParameters['dir'] == 'inflow',
              period: DateRangePeriod.fromQuery(s.uri.queryParameters),
              navToken: s.uri.queryParameters['nav'],
            ),
          )]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.insights, builder: (_, __) => const InsightsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.upcoming, builder: (_, __) => const UpcomingScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.profile, builder: (_, __) => const ProfileScreen())]),
        ],
      ),
    ],
  );
});
