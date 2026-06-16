import 'package:flutter_test/flutter_test.dart';
import 'package:caleb_choir/models/user.dart';

void main() {
  group('User.fromMap', () {
    test('parses a full record', () {
      final user = User.fromMap({
        'id': 'u1',
        'name': '홍길동',
        'nickname': '길동',
        'email': 'a@b.com',
        'role': 'part_leader',
        'part': 'tenor',
        'partLeaderFor': 'tenor',
        'partLeaderTitle': 'assistant',
        'profileCompleted': true,
        'approvalStatus': 'approved',
        'churchId': 'c1',
        'isPlatformAdmin': true,
      });

      expect(user.id, 'u1');
      expect(user.name, '홍길동');
      expect(user.role, 'part_leader');
      expect(user.profileCompleted, isTrue);
      expect(user.isPlatformAdmin, isTrue);
      expect(user.churchId, 'c1');
    });

    test('applies safe defaults for a minimal record', () {
      final user = User.fromMap({'id': 'u2'});

      expect(user.id, 'u2');
      expect(user.name, isNull);
      expect(user.profileCompleted, isFalse);
      expect(user.isPlatformAdmin, isFalse);
      expect(user.churchId, isNull);
    });

    test('coerces a non-string id to string', () {
      expect(User.fromMap({'id': 123}).id, '123');
      expect(User.fromMap(<String, dynamic>{}).id, '');
    });
  });

  group('role getters', () {
    User withRole(String? role) => User.fromMap({'id': 'x', 'role': role});

    test('admin and church_admin are both church admins', () {
      expect(withRole('admin').isChurchAdmin, isTrue);
      expect(withRole('church_admin').isChurchAdmin, isTrue);
      expect(withRole('member').isChurchAdmin, isFalse);
    });

    test('hasManagePermission covers admin, officer, part_leader only', () {
      expect(withRole('admin').hasManagePermission, isTrue);
      expect(withRole('officer').hasManagePermission, isTrue);
      expect(withRole('part_leader').hasManagePermission, isTrue);
      expect(withRole('member').hasManagePermission, isFalse);
      expect(withRole(null).hasManagePermission, isFalse);
    });
  });

  group('canActOnPart', () {
    test('admin can act on any part', () {
      final admin = User.fromMap({'id': 'a', 'role': 'admin'});
      expect(admin.canActOnPart('tenor'), isTrue);
      expect(admin.canActOnPart('bass'), isTrue);
    });

    test('part leader can act only on their own part', () {
      final leader = User.fromMap({
        'id': 'l',
        'role': 'part_leader',
        'partLeaderFor': 'alto',
      });
      expect(leader.canActOnPart('alto'), isTrue);
      expect(leader.canActOnPart('tenor'), isFalse);
    });

    test('plain member cannot act on any part', () {
      final member = User.fromMap({'id': 'm', 'role': 'member'});
      expect(member.canActOnPart('alto'), isFalse);
    });
  });

  group('approval state', () {
    test('reflects approvalStatus', () {
      expect(User.fromMap({'id': 'x', 'approvalStatus': 'pending'}).isPending,
          isTrue);
      expect(User.fromMap({'id': 'x', 'approvalStatus': 'approved'}).isApproved,
          isTrue);
      expect(User.fromMap({'id': 'x', 'approvalStatus': 'rejected'}).isRejected,
          isTrue);
    });

    test('needsChurchSelection only when both churchId and scope are null', () {
      expect(User.fromMap({'id': 'x'}).needsChurchSelection, isTrue);
      expect(
        User.fromMap({'id': 'x', 'churchId': 'c1'}).needsChurchSelection,
        isFalse,
      );
      expect(
        User.fromMap({'id': 'x', 'approvalScope': 'platform'})
            .needsChurchSelection,
        isFalse,
      );
    });
  });

  group('labels and display', () {
    test('roleLabel falls back to 찬양대원 for unknown role', () {
      expect(User.fromMap({'id': 'x'}).roleLabel, '찬양대원');
      expect(User.fromMap({'id': 'x', 'role': 'officer'}).roleLabel, '임원');
    });

    test('part leader roleLabel combines part and title', () {
      final leader = User.fromMap({
        'id': 'x',
        'role': 'part_leader',
        'partLeaderFor': 'soprano',
        'partLeaderTitle': 'assistant',
      });
      expect(leader.roleLabel, '소프라노 부파트장');
    });

    test('partLeaderTitleLabel defaults to 파트장 for unknown title', () {
      expect(User.partLeaderTitleLabel(null), '파트장');
      expect(User.partLeaderTitleLabel('assistant'), '부파트장');
    });

    test('displayName appends nickname when present', () {
      expect(
        User.fromMap({'id': 'x', 'name': '홍길동', 'nickname': '길동'}).displayName,
        '홍길동 (길동)',
      );
      expect(
        User.fromMap({'id': 'x', 'name': '홍길동'}).displayName,
        '홍길동',
      );
    });

    test('legacy part keys map to 밴드', () {
      expect(User.fromMap({'id': 'x', 'part': 'guitar'}).partLabel, '밴드');
      expect(User.fromMap({'id': 'x', 'part': 'drum'}).partLabel, '밴드');
      expect(User.fromMap({'id': 'x', 'part': 'tenor'}).partLabel, '테너');
    });

    test('partInitial returns first char of label or ?', () {
      expect(User.fromMap({'id': 'x', 'part': 'alto'}).partInitial, '알');
      expect(User.fromMap({'id': 'x'}).partInitial, '?');
    });
  });
}
