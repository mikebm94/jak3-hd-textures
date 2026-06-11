using namespace System.Collections.Generic
using namespace System.IO


# A chaiNNer chain used in workflows to upscale textures.
class Chain {
	# The name of the chain (basename of the chain file.)
	[string] $Name

	# The input override ID for the 'Directory' input of the 'Load Images' node.
	# Used by workflows to point it's chain to the correct texture input directory.
	[string] $LoadDirectoryInputID

	# The input override ID for the 'Directory' input of the 'Save Images' node.
	# Used by workflows to point it's chain to the correct texture output directory.
	[string] $SaveDirectoryInputID
}


# Overrides a node's input within a chain.
# Used by workflows to supply upscale model filepaths or change some other input data.
class InputOverride {
	# Describes the input being overridden, such as the node and input name.
	# Used in error messages. Example: 'Load Model (PyTorch) -> Model'
	[string] $Description

	# The ID of the node's input.
	# Obtained in chaiNNer by right-clicking the input and clicking 'Copy Input Override Id'.
	[string] $ID

	# The value to provide when overriding the input.
	[string] $Value

	# If the value is a path, set to true to specify that the path is relative to the project directory
	# and should be resolved to an absolute path before passing to chaiNNer.
	# Useful for specifying model paths (e.g. 'models/4x-PBRify_UpscalerV4.safetensors')
	[bool] $IsRelativePath = $false

	# If the value is a path, throw an error if it doesn't exist before attempting to run the chain.
	[bool] $PathMustExist = $false
}


# Defines a method for upscaling textures.
# Consists of a chaiNNer chain used to process the textures, and the data
# that will be provided to the chain (model files, etc.) when running it.
class Workflow {
	# The name of the workflow. Will serve as the name of the subdirectories under `textures/original/`
	# and `textures/upscaled/` where textures associated with the workflow are placed.
	[string] $Name

	# The chain used to process the textures.
	# If null, no textures are processed. (Used for the dummy workflow 'Manual' since they're upscaled by hand.)
	[Chain] $Chain

	# The inputs to override when running the chain.
	[InputOverride[]] $InputOverrides
}


# Assigns a set of textures to an upscale workflow.
class TextureGroup {
	# The name of the texture group.
	[string] $Name

	# The workflow used to upscale the textures.
	# If null, the textures will not be obtained or upscaled.
	[Workflow] $Workflow

	# The names of the textures belonging to the group.
	# (Basename of the file with no extension or subdirectory, e.g. 'airlock-door-bolt')
	[string[]] $TextureNames
}


# Options configuring which textures get upscaled and which workflows to use.
class UpscaleOptions {
	# The defined chains that can be used in workflows, by name.
	[Dictionary[string, Chain]] $Chains = [Dictionary[string, Chain]]::new()

	# The defined texture upscale workflows, by name.
	[Dictionary[string, Workflow]] $Workflows = [Dictionary[string, Workflow]]::new()

	# The defined groups that assign textures to their upscale workflows, by name.
	[Dictionary[string, TextureGroup]] $TextureGroups = [Dictionary[string, TextureGroup]]::new()

	# The upscale workflow to use on textures unless otherwise specified.
	[Workflow] $DefaultWorkflow = $null

	# Maps texture names to their respective texture groups.
	[Dictionary[string, TextureGroup]] $TextureGroupMap = [Dictionary[string, TextureGroup]]::new()


	UpscaleOptions([string] $json) {
		$raw_options = $json | ConvertFrom-Json -ErrorAction Stop

		foreach ($chain in $raw_options.Chains) {
			$this.AddChain($chain.Name, $chain.LoadDirectoryInputID, $chain.SaveDirectoryInputID)
		}

		foreach ($workflow in $raw_options.Workflows) {
			$this.AddWorkflow($workflow.Name, $workflow.Chain, $workflow.InputOverrides)
		}

		if (-not [string]::IsNullOrEmpty($raw_options.DefaultWorkflow)) {
			$default_workflow = $this.Workflows[$raw_options.DefaultWorkflow]

			if ($null -eq $default_workflow) {
				throw "'DefaultWorkflow': Workflow '$( $raw_options.DefaultWorkflow )' does not exist."
			}

			$this.DefaultWorkflow = $default_workflow
		}

		foreach ($group in $raw_options.TextureGroups) {
			$this.AddTextureGroup($group.Name, $group.Workflow, $group.TextureNames)
		}
	}


	[void] AddChain([string] $name, [string] $load_dir_input_id, [string] $save_dir_input_id) {
		if ([string]::IsNullOrWhiteSpace($name)) {
			throw "In 'Chains': 'Name' must not be empty."
		}

		if ([string]::IsNullOrWhiteSpace($load_dir_input_id)) {
			throw "In chain '${name}': 'LoadDirectoryInputID' must not be empty."
		}

		if ([string]::IsNullOrWhiteSpace($save_dir_input_id)) {
			throw "In chain '${name}': 'SaveDirectoryInputID' must not be empty."
		}

		if ($this.Chains.ContainsKey($name)) {
			throw "In chain '${name}': A chain named '${name}' already exists."
		}

		$this.Chains[$name] = [Chain]@{
			Name = $name
			LoadDirectoryInputID = $load_dir_input_id
			SaveDirectoryInputID = $save_dir_input_id
		}
	}


	[void] AddWorkflow([string] $name, [string] $chain_name, [InputOverride[]] $input_overrides) {
		if ([string]::IsNullOrWhiteSpace($name)) {
			throw "In 'Workflows': 'Name' must not be empty."
		}

		if (-not (IsValidFilename $name)) {
			throw "In Workflow '${name}': Workflow name must contain only characters safe for filenames."
		}

		if ($this.Workflows.ContainsKey($name)) {
			throw "In Workflow '${name}': A Workflow named '${name}' already exists."
		}

		[Chain]$chain = $null

		if (-not [string]::IsNullOrEmpty($chain_name)) {
			$chain = $this.Chains[$chain_name]

			if ($null -eq $chain) {
				throw "In Workflow '${name}': A Chain named '${chain_name}' does not exist."
			}
		}

		foreach ($input_override in $input_overrides) {
			if ([string]::IsNullOrWhiteSpace($input_override.ID)) {
				throw "In Workflow '${name}': In 'InputOverrides': 'ID' must not be empty."
			}
		}

		$this.Workflows[$name] = [Workflow]@{
			Name = $name
			Chain = $chain
			InputOverrides = $input_overrides
		}
	}


	[void] AddTextureGroup([string] $name, [string] $workflow_name, [string[]] $texture_names) {
		if ([string]::IsNullOrWhiteSpace($name)) {
			throw "In 'TextureGroups': 'Name' must not be empty."
		}

		if ($this.TextureGroups.ContainsKey($name)) {
			throw "In TextureGroup '${name}': A TextureGroup named '${name}' already exists."
		}

		[Workflow]$workflow = $null

		if (-not [string]::IsNullOrEmpty($workflow_name)) {
			$workflow = $this.Workflows[$workflow_name]

			if ($null -eq $workflow) {
				throw "In TextureGroup '${name}': A Workflow named '${workflow_name}' does not exist."
			}
		}

		$group = [TextureGroup]@{
			Name = $name
			Workflow = $workflow
			TextureNames = $texture_names
		}

		$this.TextureGroups[$name] = $group

		foreach ($texture_name in $texture_names) {
			$existing_group = $this.TextureGroupMap[$texture_name]
			if ($null -ne $existing_group) {
				Write-Warning (
					"In TextureGroup '${name}': Texture '${texture_name}' " +
					"was previously assigned to group '$( $existing_group.Name )'."
				)
			}

			$this.TextureGroupMap[$texture_name] = $group
		}
	}
}


<#
.SYNOPSIS
Reads the options configuring what textures get upscaled and which workflows to use.
#>
function Read-UpscaleOptions {
	[CmdletBinding()]
	[OutputType([UpscaleOptions])]
	param()

	Write-Host 'Reading upscale options ...'
	$upscale_options_path = Join-Path $ProjectDir 'upscale-options.json'
	[UpscaleOptions]::new([File]::ReadAllText($upscale_options_path))
}
