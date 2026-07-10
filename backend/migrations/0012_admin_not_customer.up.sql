-- Admins are staff, not customers: drop the customer role from every
-- admin/super_admin account. Login stopped granting customer to staff
-- and the app no longer shows customer features to them.
DELETE FROM user_roles ur
 USING roles c
 WHERE ur.role_id = c.id
   AND c.name = 'customer'
   AND EXISTS (SELECT 1
                 FROM user_roles staff
                 JOIN roles a ON a.id = staff.role_id
                WHERE staff.user_id = ur.user_id
                  AND a.name IN ('admin', 'super_admin'));
