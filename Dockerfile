# Modified from Jupyter Development Team.
# Distributed under the terms of the Modified BSD License.

# Ubuntu 20.04 (focal)
# https://hub.docker.com/_/ubuntu/?tab=tags&name=focal
# OS/ARCH: linux/amd64
ARG ROOT_CONTAINER=ubuntu:focal-20200703@sha256:d5a6519d9f048100123c568eb83f7ef5bfcad69b01424f420f17c932b00dea76

ARG BASE_CONTAINER=$ROOT_CONTAINER
FROM $BASE_CONTAINER

LABEL maintainer="Blake Fleischer"
ARG NB_USER="jovyan"
ARG NB_UID="1000"
ARG NB_GID="100"

# Fix DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

# Install all OS dependencies for notebook server that starts but lacks all
# features (e.g., download as all possible file formats)
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update \
 && apt-get install -yq --no-install-recommends \
    build-essential \
    bzip2 \
    ca-certificates \
    ffmpeg \
    fonts-dejavu \
    fonts-liberation \
    fonts-liberation \
    gcc \
    gfortran \
    git \
    graphviz \
    jed \
    less \
    libgtk2.0-0 \
    libkrb5-dev \
    libsqlite3-dev \
    libssl-dev \
    libxext-dev \
    libxslt1.1 \
    libxtst-dev \ 
    libxxf86vm1 \
    locales \
    netcat \
    run-one \
    sudo \
    tmux \
    unattended-upgrades \
    unzip \
    vim \
    wget \
    zlib1g-dev \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen

# Configure environment
ENV CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    NB_USER=$NB_USER \
    NB_UID=$NB_UID \
    NB_GID=$NB_GID \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8
ENV PATH=$CONDA_DIR/bin:$PATH \
    HOME=/home/$NB_USER

# Copy a script that we will use to correct permissions after running certain commands
COPY scripts/fix-permissions /usr/local/bin/fix-permissions
RUN chmod a+rx /usr/local/bin/fix-permissions

# Enable prompt color in the skeleton .bashrc before creating the default NB_USER
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc

# Create NB_USER wtih name jovyan user with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    useradd -m -s /bin/bash -N -u $NB_UID $NB_USER && \
    mkdir -p $CONDA_DIR && \
    chown $NB_USER:$NB_GID $CONDA_DIR && \
    chmod g+w /etc/passwd && \
    fix-permissions $HOME && \
    fix-permissions $CONDA_DIR

## Copy .condarc for strict channel priority to conda-forge so channel mizing won't
## cause problems down the road - potentially needed for Conda 4.6.14
#COPY python_plst/.condarc ${HOME}
#RUN chown $NB_USER:$NB_GID ${HOME}/.condarc

USER $NB_UID
WORKDIR $HOME
ARG PYTHON_VERSION=default

# Setup work directory for backward-compatibility
RUN mkdir /home/$NB_USER/work && \
    fix-permissions /home/$NB_USER

# Install conda as jovyan and check the md5 sum provided on the download site
ENV MINICONDA_VERSION=4.8.3 \
    MINICONDA_MD5=751786b92c00b1aeae3f017b781018df \
    CONDA_VERSION=4.8.3 \
    CONDA_INSTALLERS=/tmp/conda_install
# Conda 4.6.14 might be needed for compatibility, but takes extremely long to resolve dependencies
#ENV MINICONDA_VERSION=4.6.14 \
#    MINICONDA_MD5=718259965f234088d785cad1fbd7de03 \
#    CONDA_VERSION=4.6.14 \
#    CONDA_INSTALLERS=/tmp/conda_install

WORKDIR /tmp
RUN mkdir -p ${CONDA_INSTALLERS} && \
    cd ${CONDA_INSTALLERS} && \ 
    wget --quiet https://repo.continuum.io/miniconda/Miniconda3-py37_${MINICONDA_VERSION}-Linux-x86_64.sh && \
    echo "${MINICONDA_MD5} *Miniconda3-py37_${MINICONDA_VERSION}-Linux-x86_64.sh" | md5sum -c - && \
    /bin/bash Miniconda3-py37_${MINICONDA_VERSION}-Linux-x86_64.sh -f -b -p $CONDA_DIR && \
    echo "conda ${CONDA_VERSION}" >> $CONDA_DIR/conda-meta/pinned && \
    conda config --system --prepend channels conda-forge && \
    conda config --system --set auto_update_conda false && \
    conda config --system --set show_channel_urls true && \
    conda config --system --set channel_priority strict && \
    if [ ! $PYTHON_VERSION = 'default' ]; then conda install --yes python=$PYTHON_VERSION; fi && \
    conda list python | grep '^python ' | tr -s ' ' | cut -d '.' -f 1,2 | sed 's/$/.*/' >> $CONDA_DIR/conda-meta/pinned && \
    conda install --quiet --yes conda && \
    conda install --quiet --yes pip && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER

# Install conda packages from locally saved packages
COPY python_plst/requirements_docker_conda.txt /tmp/
COPY python_plst/requirements_docker_pip.txt /tmp/

#### CONDA INSTALL Two sections. Fresh install is for updating packages.
## Fresh Conda Install
RUN conda install --download-only -c conda-forge --file /tmp/requirements_docker_conda.txt --strict-channel-priority
RUN cd ${CONDA_DIR}/pkgs && \
    find . -maxdepth 1 -type f | tar -czvf ${CONDA_INSTALLERS}/conda_libs.tar.gz -T -
RUN conda install --offline -c local --file /tmp/requirements_docker_conda.txt --quiet --yes && \
    conda list tini | grep tini | tr -s ' ' | cut -d ' ' -f 1,2 >> $CONDA_DIR/conda-meta/pinned

RUN mkdir -p ${CONDA_INSTALLERS}/pip-packages/ && \
    pip download -r /tmp/requirements_docker_pip.txt --dest ${CONDA_INSTALLERS}/pip-packages/ && \
    pip install --no-index --find-links=${CONDA_INSTALLERS}/pip-packages -r /tmp/requirements_docker_pip.txt 
RUN cd ${CONDA_INSTALLERS}/pip-packages/ && \
    find . -maxdepth 1 -type f | tar -czvf ${CONDA_INSTALLERS}/pip_libs.tar.gz -T - && \
## Reinstall CONDA and PIP from PREV Fresh Install
#COPY python_pkgs/conda_pkgs.tar.gz ${CONDA_INSTALLERS}/
#COPY python_pkgs/pip_pkgs.tar.gz ${CONDA_INSTALLERS}/
#RUN tar -C $CONDA_DIR/pkgs/ -xvf ${CONDA_INSTALLERS}/pi_pkgs.tar.gz && \
#    conda install --offline -c local --file /tmp/requirements_docker_conda.txt && \
#    # Install pip packages
#    mkdir ${CONDA_INSTALLERS}/pip-packages && \
#    tar -C ${CONDA_INSTALLERS}/pip-packages/ -xvf ${CONDA_INSTALLERS}/pip_pkgs.tar.gz && \
#    rm -rf ${CONDA_INSTALLERS} && \
######
#
######
    conda clean --all -f -y && \
    # Activate ipywidgets extension in the environment that runs the notebook server
    jupyter nbextension enable --py widgetsnbextension --sys-prefix && \
    # Also activate ipywidgets extension for JupyterLab
    # Check this URL for most recent compatibilities
    # https://github.com/jupyter-widgets/ipywidgets/tree/master/packages/jupyterlab-manager
    jupyter labextension install @jupyter-widgets/jupyterlab-manager@^2.0.0 --no-build && \
    jupyter labextension install @bokeh/jupyter_bokeh@^2.0.0 --no-build && \
    jupyter labextension install jupyter-matplotlib@^0.7.2 --no-build && \
    jupyter labextension install @jupyterlab/toc --no-build && \
    jupyter lab build --dev-build=False --minimize=False -y && \
    jupyter lab clean -y && \
    npm cache clean --force && \
    rm -rf "/home/${NB_USER}/.cache/yarn" && \
    rm -rf "/home/${NB_USER}/.node-gyp" && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}" && \
    # Remove all unnecessary files in /tmp to save space
    find /tmp -user ${NB_USER} | xargs rm -rf

# Install facets which does not have a pip or conda package at the moment
WORKDIR /tmp
RUN git clone https://github.com/PAIR-code/facets.git && \
    jupyter nbextension install facets/facets-dist/ --sys-prefix && \
    rm -rf /tmp/facets && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"

# Import matplotlib the first time to build the font cache.
ENV XDG_CACHE_HOME="/home/${NB_USER}/.cache/"

RUN MPLBACKEND=Agg python -c "import matplotlib.pyplot" && \
    fix-permissions "/home/${NB_USER}"

## Install PyCharm
ARG PYCHARM_SOURCE=https://download.jetbrains.com/python/pycharm-community-anaconda-2020.2.tar.gz
USER root
WORKDIR /opt/pycharm
RUN curl -fsSL $PYCHARM_SOURCE -o /opt/pycharm/installer.tgz && \
    tar --strip-components=1 -xzf installer.tgz && \
    rm installer.tgz && \
    python /opt/pycharm/plugins/python-ce/helpers/pydev/setup_cython.py build_ext --inplace && \
    fix-permissions $WORKDIR

EXPOSE 8888

# Configure container startup
ENTRYPOINT ["tini", "-g", "--"]
#CMD ["start-notebook.sh"]
CMD ["wrapper_start.sh"]

# Copy local files as late as possible to avoid cache busting
COPY scripts/start.sh scripts/start-notebook.sh /usr/local/bin/
COPY scripts/wrapper_start.sh /usr/local/bin
COPY scripts/jupyter_notebook_config.py /etc/jupyter/
RUN chmod +x /usr/local/bin/start.sh /usr/local/bin/wrapper_start.sh /usr/local/bin/start-notebook.sh

# Fix permissions on /etc/jupyter as root
USER root
RUN fix-permissions /etc/jupyter/
RUN echo "${NB_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Switch back to jovyan to avoid accidental container runs as root
USER $NB_UID

WORKDIR $HOME
