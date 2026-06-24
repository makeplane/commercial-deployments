python manage.py seed_project_at_scale --workspace_slug seedws1 --users 5000 --num_projects 1 --skip_phase workspace_feature,workspace_types,workspace_properties,type_property_bindings,project_features,project_types,memberships,states,labels,cycles,modules,milestones,issues,assignees,label_issues,cycle_issues,module_issues,milestone_issues,property_values,dependencies,relations



python manage.py seed_project_at_scale --workspace_slug seedws1 --users 5000 --num_projects 1 --skip_phase workspace_feature,workspace_types,workspace_properties,type_property_bindings,project_features,project_types,memberships,states,labels,cycles,modules,milestones,issues,assignees,label_issues,cycle_issues,module_issues,milestone_issues,property_values,dependencies,relations

```
from django.contrib.auth.hashers import make_password
from plane.db.models import User

# letters-only, to match the seeder's rule
new_pw = "loadtestpassword"
hashed = make_password(new_pw)

qs = User.objects.filter(email__icontains="@seed.plane.so")
print("users:", qs.count())
qs.update(password=hashed, is_password_autoset=False)
```



```
import random

from django.core.management import call_command

from plane.db.models import (
    Project,
    ProjectMember,
    Role,
    User,
    Workspace,
    WorkspaceMember,
)

# ── config ────────────────────────────────────────────────────────────────
WORKSPACE_SLUG = "scale"
# The users you just seeded; use "plane.so" for real teammates.
EMAIL_DOMAIN = "seed.plane.so"

# Workspace role. 25/owner = what you asked. For the supported path use 20/"admin".
WS_ROLE_NUM, WS_ROLE_SLUG = 25, "owner"

# Project role — project max is admin (no owner at project scope).
PROJ_ROLE_NUM, PROJ_ROLE_SLUG = 20, "admin"

BATCH = 2000
# ────────────────────────────────────────────────────────────────────────────

ws = Workspace.objects.filter(slug=WORKSPACE_SLUG).first()
assert ws, f"Workspace '{WORKSPACE_SLUG}' not found"


def load_role(ns, slug):
    r = Role.objects.filter(
        workspace=ws,
        namespace=ns,
        slug=slug,
        is_system=True,
        deleted_at__isnull=True,
    ).first()
    assert r, f"System {ns} role '{slug}' missing — run init_permissions first."
    return r


ws_role = load_role("workspace", WS_ROLE_SLUG)
proj_role = load_role("project", PROJ_ROLE_SLUG)

user_ids = list(
    User.objects.filter(email__iendswith=f"@{EMAIL_DOMAIN}", is_active=True)
    .order_by("id")
    .values_list("id", flat=True)
)
assert user_ids, f"No active users with an @{EMAIL_DOMAIN} email."

projects = list(
    Project.objects.filter(workspace=ws, deleted_at__isnull=True).order_by("created_at")
)
assert projects, "No projects in this workspace."

print(
    f"{len(user_ids)} @{EMAIL_DOMAIN} users → role {WS_ROLE_NUM}/{WS_ROLE_SLUG}, "
    f"joining {len(projects)} projects…"
)

# ── 1) Workspace membership: create missing + set role on existing ──────────
existing = set(
    WorkspaceMember.objects.filter(
        workspace=ws, member_id__in=user_ids, deleted_at__isnull=True
    ).values_list("member_id", flat=True)
)

if existing:
    WorkspaceMember.objects.filter(
        workspace=ws, member_id__in=list(existing), deleted_at__isnull=True
    ).update(role_ref=ws_role, role=WS_ROLE_NUM)

ws_buf = [
    WorkspaceMember(
        workspace=ws,
        member_id=uid,
        role_ref=ws_role,
        role=WS_ROLE_NUM,
        is_active=True,
    )
    for uid in user_ids
    if uid not in existing
]
WorkspaceMember.objects.bulk_create(ws_buf, batch_size=BATCH, ignore_conflicts=True)
print(
    f"  workspace: created {len(ws_buf)}, "
    f"set role on {len(existing)} existing → {WS_ROLE_NUM}"
)

# ── 2) Project membership for every project ─────────────────────────────────
for p in projects:
    already = set(
        ProjectMember.objects.filter(
            project=p, member_id__in=user_ids, deleted_at__isnull=True
        ).values_list("member_id", flat=True)
    )
    pm_buf = [
        ProjectMember(
            workspace=ws,
            project=p,
            member_id=uid,
            role_ref=proj_role,
            role=PROJ_ROLE_NUM,
            is_active=True,
            sort_order=random.randint(0, 65535),
        )
        for uid in user_ids
        if uid not in already
    ]
    ProjectMember.objects.bulk_create(pm_buf, batch_size=BATCH, ignore_conflicts=True)
    print(f"  {p.identifier}: +{len(pm_buf)} ({len(already)} already members)")

# ── 3) Backfill ReBAC tuples (bulk_create bypassed PermissionSyncMixin) ──────
print("  reconciling ReBAC ResourcePermission tuples…")
call_command("reconcile_resource_permissions", workspace=ws.slug, apply=True)

print("Done — refresh the Members page.")
```
