#!/usr/bin/env bash
# set -e -x

#
## SETUP
#

set -euo pipefail
unset CDPATH; cd "$( dirname "${BASH_SOURCE[0]}" )"; cd "$(pwd -P)"

fatal() { echo -e "$1"; exit 1; }
function join_by { local IFS="$1"; shift; echo "$*"; }

# define here the local folders for your installation of CBSTools and Nighres
cbstools_local="/home/pilou/Code/github/cbstools-public"
nighres_local="/home/pilou/Code/github/nighres"

# Check the system has the necessary commands
hash wget tar javac jar python pip 2>/dev/null || fatal "This script needs the following commands available: wget tar javac jar python pip"

# Check for setuptools and wheels
pip_modules=$(pip list --format columns | tr -s ' ' | cut -f 1 -d ' ')
echo "${pip_modules}" | grep setuptools > /dev/null || fatal 'This script requires setuptools.\nInstall with `pip install --upgrade setuptools`'
echo "${pip_modules}" | grep wheel > /dev/null || fatal 'This script requires wheel.\nInstall with `pip install --upgrade wheel`'

# echo "Before detection: $JAVA_HOME"

# Set the JAVA_HOME variable if it is not set
detected_home=$(java -XshowSettings:properties -version 2>&1 | tr -d ' '| grep java.home | cut -f 2 -d '=')
export JAVA_HOME=${JAVA_HOME:-"$detected_home"}
# echo "After detection: $JAVA_HOME"

# Check that JCC is installed
#echo "${pip_modules}" | grep JCC > /dev/null || fatal 'This script requires JCC.\nInstall with `apt-get install jcc` or equivalent and `pip install jcc`'

# Attempt to check for python development headers
# Inspired by https://stackoverflow.com/a/4850603
python_include_path=$(python -c "from distutils import sysconfig as s; print s.get_config_vars()['INCLUDEPY']")
test -f "${python_include_path}/Python.h" || fatal 'This script requires python development headers.\nInstall with `apt-get install python-dev`, or \n             `apt-get install python3-dev`, or equivalent'

#
## COMPILE
#

# Java dependencies. Order matters
deps=(
	"."
	"lib/Jama-mipav.jar"
	"lib/commons-math3-3.5.jar"
)
deps_list=$(join_by ":" "${deps[@]}")

# List of library files needed to run the cbstools core functions
source cbstools-lib-files.sh
echo $cbstools_files # result is in $cbstools_files

cbstools_list=$(join_by " " "${cbstools_files[@]}")

# Compilation options
javac_opts=(
	# "-d build"        # Output dir
	"-Xlint:none"     # Disable all warnings
	# "-server"         # ?
	"-g"              # Generate all debugging info
	"-O"              # ?
	"-deprecation"    # Show information about deprecated Java calls
	"-encoding UTF-8" # Require UTF-8, rather than platform-specifc
)

echo "Compiling..."
#cd cbstools-public
cd $cbstools_local
mkdir -p build
javac -cp ${deps_list} ${javac_opts[@]} de/mpg/cbs/core/*/*.java $cbstools_list

echo "Assembling..."
jar cf cbstools.jar     de/mpg/cbs/core/*/*.class
jar cf cbstools-lib.jar de/mpg/cbs/*/*.class


#
## WRAP TO PYTHON
#

jcc_args=(
	# All public methods in this JAR will be wrapped
	"--jar cbstools.jar"

	# Dependencies
	"--include cbstools-lib.jar"
	"--include lib/commons-math3-3.5.jar"
	"--include lib/Jama-mipav.jar"

	# Name the python module
	"--python cbstools"

	# Java VM heap size limit
	"--maxheap 4096M"

	# Compile
	"--build"
)

python -m jcc ${jcc_args[@]}


#
# Assemble PYPI package
#

echo "Copying necessary files for nires pypi package..."

cp -rv build/cbstools/ $nighres_local/
# Find and copy the shared object file for the current architecture
find build/ -type f | grep '.so$' | head -n 1 | xargs -I '{}' -- cp '{}' $nighres_local/cbstools/_cbstools.so
cd $nighres_local
