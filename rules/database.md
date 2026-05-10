---
paths:
  - "**/*.py"
  - "**/*.sql"
  - "**/migrations/**"
  - "**/models/**"
---

# Database

## Naming

- Tables: plural snake_case (`users`, `order_items`)
- Foreign keys: `{singular}_id` (`user_id`)
- Timestamps: always add `created_at`, `updated_at`

## Model Pattern (SQLAlchemy 2.0)

```python
class User(Base):
    __tablename__ = "users"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now(), onupdate=func.now())

    # Relationship with eager loading default
    orders: Mapped[list["Order"]] = relationship(back_populates="user", lazy="selectin")

class Order(Base):
    __tablename__ = "orders"

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"), index=True)  # ALWAYS index FKs
```

## Prevent N+1 Queries

```python
# WRONG: triggers N queries
users = (await session.execute(select(User))).scalars().all()
for u in users: print(u.orders)  # Each access = 1 query

# CORRECT: eager load
from sqlalchemy.orm import selectinload
users = await session.execute(select(User).options(selectinload(User.orders)))
```

## Use Database Aggregations

```python
# WRONG: loads all rows into memory
count = len((await session.execute(select(User))).scalars().all())

# CORRECT: database count
count = (await session.execute(select(func.count()).select_from(User))).scalar_one()
```

## Transactions

```python
async with session.begin():
    # All operations here are atomic
    session.add(order)
    session.add(payment)
    # Auto-commits on exit, auto-rollbacks on exception
```

## Migrations — additive-only discipline

If your deploy pipeline rolls back image SHAs but not DB schema (a common production pattern, since DB downgrades are rarely reversible), migrations must be **additive-only** — old code from the prior release must be able to safely talk to the newer schema after a rollback.

- ✅ ADD column with DEFAULT or NULL (old code ignores the new column)
- ✅ ADD table (old code ignores the new table)
- ✅ ADD index (transparent to old code)
- ✅ ADD nullable foreign key
- ❌ DROP column / DROP table — old code may still reference it
- ❌ RENAME column / RENAME table — old code can't find it
- ❌ NOT-NULL constraint added without backfill+default — old code's INSERTs may break
- ❌ Type narrowing (e.g. `VARCHAR(255)` → `VARCHAR(64)`) — old code's longer strings break

For a destructive change, use the **expand-contract pattern** across three releases:

1. **Expand** (release N): add the new column/table; old code keeps writing the old shape; new code dual-writes to both.
2. **Backfill + cutover** (release N+1): new code reads from the new shape only; old shape still exists but unused.
3. **Contract** (release N+2): drop the old column/table.

Each release is purely additive over the previous one, so a rollback within any single release stays safe.

If a destructive change is genuinely required (e.g. emergency security fix), coordinate with the team to disable auto-rollback for that deploy — treat it as a one-way migration with a maintenance window.

## Rules

1. ALWAYS add `created_at` and `updated_at` columns
2. ALWAYS index foreign key columns
3. ALWAYS use eager loading (`selectinload`/`joinedload`) to prevent N+1
4. ALWAYS use parameterized queries (ORMs do this automatically)
5. ALWAYS write additive-only migrations — use expand-contract for destructive changes (see "Migrations" section above)
6. NEVER use `len()` on query results — use `func.count()`
7. NEVER build SQL with string concatenation
8. PREFER UUID primary keys for distributed systems
9. PREFER storing money as integers (cents)
