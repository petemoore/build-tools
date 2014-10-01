#!/bin/bash -eu

# interactive mode
cat << EOF

Which type of slave would you like?

Build                           Try                             Test
  Linux                           Linux                           Android
    01) b-linux64-hp                08) b-linux64-hp                14) panda
    02) b-linux64-ix                09) b-linux64-ix                15) tst-emulator64-ec2
    03) bld-linux64-ec2             10) bld-linux64-spot            16) tst-emulator64-spot
    04) bld-linux64-spot          Mac                             Linux
  Mac                               11) bld-lion-r5                 17) talos-linux32-ix
    05) bld-lion-r5               Windows                           18) talos-linux64-ix
  Windows                           12) b-2008-ix                   19) tst-linux32-spot
    06) b-2008-ix                   13) b-2008-sm                   20) tst-linux64-spot
    07) b-2008-sm                                                 Mac
                                                                    21) t-mavericks-r5
                                                                    22) talos-mtnlion-r5
                                                                    23) t-snow-r4
                                                                  Windows
                                                                    24) t-w732-ix
                                                                    25) t-w864-ix
                                                                    26) t-xp32-ix
                                                                    27) tst-w64-ec2

EOF

echo -n "Slave type: "
read slave_type
while ! echo "${slave_type}" | grep -qx '[[:space:]]*[0-9][0-9]*[[:space:]]*' || [ "${slave_type}" -eq 0 ] || [ "${slave_type}" -gt 27 ]; do
    echo -n "Slave type must be a number between 1 and 27, please try again: "
    read slave_type
done
slave_type="$((slave_type))"
echo "You chose slave type: ${slave_type}"

echo
echo -n "Bug number: "
read bug
while ! echo "${bug}" | grep -qx '[[:space:]]*[0-9][0-9]*[[:space:]]*' || [ "${slave_type}" -eq 0 ] || [ "${slave_type}" -gt 9999999 ]; do
    echo -n "Bug number must be a number between 1 and 9999999, please try again: "
    read bug
done
bug="$((bug))"
echo "You chose bug: ${bug}"
echo

bugzilla_json="$(mktemp -t bugzilla.XXXXXXXXXX)"
curl -s "https://bugzilla.mozilla.org/rest/bug/${bug}" > "${bugzilla_json}"
email="$(cat "${bugzilla_json}" | sed -n 's/.*"creator_detail":{"email":"\([^"]*\).*/\1/p')"
user="$(cat "${bugzilla_json}" | sed -n 's/.*"creator_detail":{"email":"[^"]*","real_name":"[^\[]*\[:\([^]]*\).*/\1/p')"
name="$(cat "${bugzilla_json}" | sed -n 's/.*"creator_detail":{"email":"[^"]*","real_name":"\([^\["]*\).*/\1/p' | xargs)"
rm "${bugzilla_json}"

[ -z "${user}" ] && user="$(echo "${email}" | sed -n 's/^\([a-zA-Z0-9]*\).*/\1/;y/ZAQWSXCDERFVBGTYHNMJUIKLOP/zaqwsxcderfvbgtyhnmjuiklop/;p')"
while [ -z "${user}" ]; do
    echo -n "Enter user name (not able to retrieve one from bugzilla): "
    read user
    user="$(echo "${user}" | sed -n 's/.*"creator_detail":{"email":"[^"]*","real_name":"[^\[]*\[:\([^]]*\).*/\1/p')"
done
echo "  * Using user name: '${user}'"

while [ -z "${name}" ]; do
    echo -n "Enter real name (not able to retrieve one from bugzilla): "
    read name
done

echo "  * Using real name: '${name}'"

unset arch slavetype slave_class
case "${slave_type}" in
    3) arch=64 slavetype=bld-linux64-ec2 slave_class=builder;;
    4) arch=64 slavetype=bld-linux64-spot slave_class=builder;;
    10) arch=64 slavetype=bld-linux64-spot slave_class=builder;;
    19) arch=32 slavetype=tst-linux32-spot slave_class=tester;;
    20) arch=64 slavetype=tst-linux64-spot slave_class=tester;;
esac

case "${slave_class}" in
    builder)  image_config="dev-linux${arch}"  domain="dev.releng.use1.mozilla.com" instance_data="us-east-1.instance_data_dev.json";;
    tester)   image_config="tst-linux${arch}" domain="test.releng.use1.mozilla.com" instance_data="us-east-1.instance_data_tests.json";;
esac

[ -n "${arch}" ] && echo "  * Using architecture: ${arch} bit"
[ -n "${slavetype}" ] && echo "  * Using slave type: ${slavetype}"
[ -n "${slave_class}" ] && echo "  * Using slave class: ${slave_class}"
[ -n "${image_config}" ] && echo "  * Using cloud tools image config: ${image_config}"
[ -n "${domain}" ] && echo "  * Using network domain: ${domain}"
[ -n "${instance_data}" ] && echo "  * Using cloud tools instance data: ${instance_data}"

host="$slavetype-$user"
[ -n "${instance_data}" ] && echo "  * Using host name: ${host}"

case "${slave_type}" in
    3 | 4 | 10 | 19 | 20)
        echo "  * Provisioning an AWS machine..."

        ssh 'buildduty@aws-manager1.srv.releng.scl3.mozilla.com' "
            # double-check that the IP address is not in use by some other machine
            ip=\$(python 'cloud-tools/scripts/free_ips.py' -c 'cloud-tools/configs/${image_config}' -r us-east-1 -n1)
            host \"\$ip\"
            # create a DNS entry
            # use full LDAP e.g. 'user@mozilla.com'
            invtool A create --ip '$ip' --fqdn '${host}.${domain}' --private  --description 'bug ${bug}: loaner for ${user}'
            # create a DNS reverse-mapping (required for puppet certs to work properly)
            invtool PTR create --ip '$ip' --target '${host}.${domain}' --private --description 'bug ${bug}: loaner for ${user}'
        "

        # wait 20 minutes for DNS to propagate...
        sleep 20m

        # below may take awhile to complete, so feel free to tail the
        # per-host logs under buildduty@aws-manager1:/builds/aws_manager/ or /root/puppetize.log on the new
        # instance (connect using the aws-releng key)
        ssh 'buildduty@aws-manager1.srv.releng.scl3.mozilla.com' "
            python 'cloud-tools/scripts/aws_create_instance.py' \\
              -c 'cloud-tools/configs/${image_config}' \\
              -r us-east-1 \\
              --loaned-to '$email' \\
              --bug '$bug' \\
              -s aws-releng \\
              -k 'secrets/aws-secrets.json' \\
              --ssh-key ~/.ssh/aws-ssh-key \\
              -i 'cloud-tools/instance_data/${instance_data}' \\
              ${host}
        "
        ;;
esac
