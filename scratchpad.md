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
from django.db import transaction

from plane.db.models import Project, ProjectMember, Role, User, Workspace

WORKSPACE_SLUG = "scale"
EMAIL_DOMAIN = "seed.plane.so"
PROJ_ROLE_NUM, PROJ_ROLE_SLUG = 20, "admin"  # project max; use 15/"contributor" for normal
BATCH = 2000

ws = Workspace.objects.filter(slug=WORKSPACE_SLUG).first()
assert ws, f"Workspace '{WORKSPACE_SLUG}' not found"

proj_role = Role.objects.filter(
    workspace=ws,
    namespace="project",
    slug=PROJ_ROLE_SLUG,
    is_system=True,
    deleted_at__isnull=True,
).first()
assert proj_role, f"System project role '{PROJ_ROLE_SLUG}' missing — run init_permissions first."

user_ids = list(
    User.objects.filter(
        email__iendswith=f"@{EMAIL_DOMAIN}", is_active=True
    ).values_list("id", flat=True)
)
assert user_ids, f"No active users with an @{EMAIL_DOMAIN} email."

projects = list(Project.objects.filter(workspace=ws, deleted_at__isnull=True))
assert projects, "No projects in this workspace."

with transaction.atomic():
    for p in projects:
        already = set(
            ProjectMember.objects.filter(
                project=p, member_id__in=user_ids, deleted_at__isnull=True
            ).values_list("member_id", flat=True)
        )
        ProjectMember.objects.bulk_create(
            [
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
            ],
            batch_size=BATCH,
            ignore_conflicts=True,
        )

call_command(
    "reconcile_resource_permissions", workspace=ws.slug, apply=True, verbosity=0
)
```
