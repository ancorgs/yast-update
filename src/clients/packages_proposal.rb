# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2006-2012 Novell, Inc. All Rights Reserved.
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail, you may find
# current contact information at www.novell.com.
# ------------------------------------------------------------------------------

# Module:	packages_proposal.ycp
#
# Author:	Arvin Schnell <arvin@suse.de>
#
# Purpose:	Let user choose packages during update.
#
# $Id$
module Yast
  class PackagesProposalClient < Client
    def main
      Yast.import "Pkg"
      textdomain "update"

      Yast.import "HTML"
      Yast.import "Packages"
      Yast.import "SpaceCalculation"
      Yast.import "PackagesUI"

      Yast.import "Update"


      @func = Convert.to_string(WFM.Args(0))
      @param = Convert.to_map(WFM.Args(1))
      @ret = {}


      if @func == "MakeProposal"
        @force_reset = Ops.get_boolean(@param, "force_reset", false)
        @language_changed = Ops.get_boolean(@param, "language_changed", false)

        # call some function that makes a proposal here:
        #
        # DummyMod::MakeProposal( force_reset );

        # Fill return map

        #	SpaceCalculation::ShowPartitionWarning ();
        @warning = SpaceCalculation.GetPartitionWarning

        # Count statistics -->
        # Pkg::GetPackages()
        #   `installed all installed packages
        #   `selected returns all selected but not yet installed packages
        #   `available returns all available packages (from the installation source)
        #   `removed all packages selected for removal

        # recreate the update summary
        @installed = Pkg.GetPackages(:installed, true)
        @selected = Pkg.GetPackages(:selected, true)
        @removed = Pkg.GetPackages(:removed, true)
        @cnt_installed = Builtins.size(@installed)
        @cnt_selected = Builtins.size(@selected)
        @cnt_removed = Builtins.size(@removed)
        Builtins.y2milestone(
          "Selected: %1, Installed: %2, Removed: %3",
          @cnt_selected,
          @cnt_installed,
          @cnt_removed
        )
        Builtins.y2milestone("Removed: %1", @removed)

        @installed_m = Builtins.listmap(@installed) { |p| { p => true } }
        @selected_m = Builtins.listmap(@selected) { |p| { p => true } }

        # packages that are both 'installed' && 'selected'
        Update.packages_to_update = Builtins.size(Builtins.filter(@selected) do |p|
          Builtins.haskey(@installed_m, p)
        end)
        # packages that are 'selected' but not 'installed'
        Update.packages_to_install = Ops.subtract(
          @cnt_selected,
          Update.packages_to_update
        )

        # packages that are 'removed' but not 'selected again'
        Update.packages_to_remove = Builtins.size(Builtins.filter(@removed) do |p|
          !Builtins.haskey(@selected_m, p)
        end)

        Builtins.y2milestone(
          "Update statistics: Updated: %1, Installed: %2, Removed: %3",
          Update.packages_to_update,
          Update.packages_to_install,
          Update.packages_to_remove
        )
        # <-- Count statistics

        @tmp = []

        # proposal for packages during update, %1 is count of packages
        @tmp = Builtins.add(
          @tmp,
          Builtins.sformat(
            _("Packages to Update: %1"),
            Update.packages_to_update
          )
        )
        # proposal for packages during update, %1 is count of packages
        @tmp = Builtins.add(
          @tmp,
          Builtins.sformat(
            _("New Packages to Install: %1"),
            Update.packages_to_install
          )
        )
        # proposal for packages during update, %1 is count of packages
        @tmp = Builtins.add(
          @tmp,
          Builtins.sformat(
            _("Packages to Remove: %1"),
            Update.packages_to_remove
          )
        )
        # part of summary, %1 is size of packages (in MB or GB)
        @tmp = Builtins.add(
          @tmp,
          Builtins.sformat(
            _("Total Size of Packages to Update: %1"),
            Packages.CountSizeToBeInstalled
          )
        )

        if Ops.greater_than(Update.solve_errors, 0)
          # the proposal for the packages requires manual invervention
          @ret = {
            "preformatted_proposal" => HTML.List(@tmp),
            # warning text
            "warning"               => _(
              "Cannot solve all conflicts. Manual intervention is required."
            ),
            "warning_level"         => :blocker
          }
        elsif Ops.greater_than(Builtins.size(@warning), 0)
          # the proposal for the packages requires manual intervention
          @ret = {
            "preformatted_proposal" => HTML.List(@tmp),
            "warning"               => Builtins.mergestring(@warning, "<br>"),
            "warning_level"         => :warning
          }
        else
          @ret = { "preformatted_proposal" => HTML.List(@tmp) }
        end

        Builtins.y2milestone(
          "Products: %1",
          Pkg.ResolvableProperties("", :product, "")
        )
        ret_ref = arg_ref(@ret)
        Packages.CheckOldAddOns(ret_ref)
        @ret = ret_ref.value
      elsif @func == "AskUser"
        @has_next = Ops.get_boolean(@param, "has_next", false)

        # call some function that displays a user dialog
        # or a sequence of dialogs here:
        #
        # sequence = DummyMod::AskUser( has_next );

        @result = call_packageselector

        # FIXME: IT'S A MESS
        # if (Pkg::PkgSolve (!Update::onlyUpdateInstalled))
        #     Update::solve_errors = 0;
        # else
        #     Update::solve_errors = Pkg::PkgSolveErrors ();

        # Fill return map

        @ret = { "workflow_sequence" => @result }
      elsif @func == "Description"
        # Fill return map.
        #
        # Static values do just nicely here, no need to call a function.

        @ret = {
          # this is a heading
          "rich_text_title" => _("Packages"),
          # this is a menu entry
          "menu_title"      => _("&Packages"),
          "id"              => "packages_stuff"
        }
      end

      deep_copy(@ret)
    end

    def call_packageselector
      options = {}

      # changing the default mode if there are some unknown packages
      if Ops.greater_than(Update.unknown_packages, 0)
        Ops.set(options, "mode", :summaryMode)
      end

      ret = PackagesUI.RunPackageSelector(options)

      if ret == :accept
        # FIXME: IT'S A MESS
        Update.solve_errors = 0
        Update.unknown_packages = 0
        Packages.base_selection_modified = true
      end

      ret
    end
  end
end

Yast::PackagesProposalClient.new.main
