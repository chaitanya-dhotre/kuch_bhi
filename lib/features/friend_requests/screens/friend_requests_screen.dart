import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../domain/entities/friend_request.dart';
import '../../../infrastructure/repositories/friend_repository_impl.dart';
import '../providers/friend_request_provider.dart';

class FriendRequestsScreen extends ConsumerWidget {
  const FriendRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(incomingRequestsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Friend Requests')),
      body: requests.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('Error loading requests: $e')),
        data: (list) => list.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 64,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.2),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No pending requests',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) =>
                    _RequestTile(request: list[i]),
              ),
      ),
    );
  }
}

class _RequestTile extends ConsumerWidget {
  const _RequestTile({required this.request});
  final FriendRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.primaryLight,
              child: Text(
                request.fromUser.displayName
                    .substring(0, 1)
                    .toUpperCase(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.fromUser.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    '@${request.fromUser.username}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            // Decline.
            IconButton(
              onPressed: () async {
                await ref
                    .read(friendRepositoryProvider)
                    .declineRequest(request.id);
              },
              icon: const Icon(Icons.close),
              style: IconButton.styleFrom(
                backgroundColor:
                    AppColors.error.withValues(alpha: 0.1),
                foregroundColor: AppColors.error,
              ),
            ),
            const SizedBox(width: 8),
            // Accept.
            IconButton(
              onPressed: () async {
                await ref
                    .read(friendRepositoryProvider)
                    .acceptRequest(request.id);
              },
              icon: const Icon(Icons.check),
              style: IconButton.styleFrom(
                backgroundColor:
                    AppColors.success.withValues(alpha: 0.1),
                foregroundColor: AppColors.success,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
