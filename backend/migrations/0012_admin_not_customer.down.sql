-- Reverse of 0012_admin_not_customer: give every staff account the
-- customer role back (the pre-separation state, where logins granted
-- customer to everyone).
INSERT INTO user_roles (user_id, role_id)
SELECT DISTINCT staff.user_id, c.id
  FROM user_roles staff
  JOIN roles a ON a.id = staff.role_id AND a.name IN ('admin', 'super_admin')
  CROSS JOIN LATERAL (SELECT id FROM roles WHERE name = 'customer') c
ON CONFLICT DO NOTHING;
