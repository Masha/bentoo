#!/usr/bin/env bats
# bats file_tags=integration
#
# Integration -- Task 1.2: `profile-set` in metadata/layout.conf.
# Requirements: R1.2, R1.4.
#
# Portage puts a BARE atom of a profile `packages` file in @profile only when
# the repository enables `profile-set`; a `*atom` goes to @system. The two
# sets must stay distinct in both directions: a bare layer atom must not land
# in @system, and branding's `*x11-themes/bentoo-logos` must not land in
# @profile.
#
# Needs no other task: the probe layer is created in a scratch copy of the
# tree's profiles/ and metadata/layout.conf.

load lib

setup() {
  need_portage
}

@test "R1.2 profile-formats keeps every existing token and adds profile-set (one line)" {
  local conf=$TREE/metadata/layout.conf
  [ "$(grep -c '^profile-formats[[:space:]]*=' "$conf")" -eq 1 ]
  local tokens
  tokens=$(sed -n 's/^profile-formats[[:space:]]*=[[:space:]]*//p' "$conf")
  for t in portage-2 profile-repo-deps profile-bashrcs profile-set; do
    words_has "$tokens" "$t" || {
      echo "profile-formats lacks $t: '$tokens'" >&2
      false
    }
  done
}

@test "R1.2/R1.4 a bare layer atom reaches @profile only; *bentoo-logos stays in @system only" {
  local ov=$BATS_TEST_TMPDIR/overlay cr=$BATS_TEST_TMPDIR/croot
  mkdir -p "$ov/metadata"
  cp -a "$TREE/profiles" "$ov/profiles"
  cp "$TREE/metadata/layout.conf" "$ov/metadata/layout.conf"
  # a throwaway layer with one bare atom (exists in ::gentoo)
  mkdir -p "$ov/profiles/targets/zz-probe"
  printf '5\n' >"$ov/profiles/targets/zz-probe/eapi"
  printf 'app-misc/screen\n' >"$ov/profiles/targets/zz-probe/packages"
  mk_croot "$cr" "$ov"
  printf '%s\n' bentoo:default/linux/amd64/23.0 bentoo:targets/zz-probe \
    >"$cr/etc/portage/make.profile/parent"

  local profile system
  profile=$(pq "$cr" set profile)
  system=$(pq "$cr" set system)

  words_has "$profile" app-misc/screen || {
    echo "bare atom missing from @profile; @profile = [$profile]" >&2
    false
  }
  ! words_has "$system" app-misc/screen || {
    echo "bare atom leaked into @system" >&2
    false
  }
  words_has "$system" x11-themes/bentoo-logos || {
    echo "*x11-themes/bentoo-logos is no longer in @system" >&2
    false
  }
  ! words_has "$profile" x11-themes/bentoo-logos || {
    echo "*x11-themes/bentoo-logos leaked into @profile" >&2
    false
  }
}
