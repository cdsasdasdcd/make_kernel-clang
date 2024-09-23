#!/bin/bash
# Patches author: weishu <twsxtd@gmail.com>
# Shell authon: xiaoleGun <1592501605@qq.com>
#               bdqllW <bdqllT@gmail.com>
#               zhlhlf <zhlhlf@gmail.com>
# Tested kernel versions: 5.4, 4.19, 4.14, 4.9
# 20240923

patch_files=(
    fs/exec.c
    fs/open.c
    fs/read_write.c
    fs/stat.c
    drivers/input/input.c
    fs/devpts/inode.c
    fs/namespace.c
)

Tonamespace=<<zhlhlf
static int can_umount(const struct path *path, int flags)
{
	struct mount *mnt = real_mount(path->mnt);

	if (flags & ~(MNT_FORCE | MNT_DETACH | MNT_EXPIRE | UMOUNT_NOFOLLOW))
		return -EINVAL;
	if (!may_mount())
		return -EPERM;
	if (path->dentry != path->mnt->mnt_root)
		return -EINVAL;
	if (!check_mnt(mnt))
		return -EINVAL;
	if (mnt->mnt.mnt_flags & MNT_LOCKED) \/* Check optimistically *\/
		return -EINVAL;
	if (flags & MNT_FORCE && !capable(CAP_SYS_ADMIN))
		return -EPERM;
	return 0;
}

int path_umount(struct path *path, int flags)
{
	struct mount *mnt = real_mount(path->mnt);
	int ret;

	ret = can_umount(path, flags);
	if (!ret)
		ret = do_umount(mnt, flags);
	\/* we mustn't call path_put() as that would clear mnt_expiry_mark *\/

	dput(path->dentry);
	mntput_no_expire(mnt);
	return ret;
}
zhlhlf


for i in "${patch_files[@]}"; do

    if grep -q "ksu" "$i" || grep -q "KernelSU" "$i"; then
        if grep -q "CONFIG_KERNELSU" "$i"; then
                echo "Warning: $i contains KernelSU"
                sed -i s/'CONFIG_KERNELSU'/'CONFIG_KSU'/g "$i"
                echo "CONFIG_KERNELSU  ---->  CONFIG_KSU"
        fi
        #有参数就是不补丁 更改配置注销为不使用
        if [ "$1" ];then
            echo "# CONFIG_KSU  ->  $i"
            sed -i s/'CONFIG_KSU'/'CONFIG_zhlhlfaaaa'/g $i            
        fi
        continue
    fi
    #没有补丁  不存在时  直接不补丁跳过
        if [ "$1" ];then
            continue
        fi
       

    case $i in

    # fs/ changes
    ## exec.c
    fs/exec.c)
        sed -i '/static int do_execveat_common/i\#ifdef CONFIG_KSU\nextern bool ksu_execveat_hook __read_mostly;\nextern int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv,\n			void *envp, int *flags);\nextern int ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr,\n				 void *argv, void *envp, int *flags);\n#endif' fs/exec.c
        if grep -q "return __do_execve_file(fd, filename, argv, envp, flags, NULL);" fs/exec.c; then
            sed -i '/return __do_execve_file(fd, filename, argv, envp, flags, NULL);/i\	#ifdef CONFIG_KSU\n	if (unlikely(ksu_execveat_hook))\n		ksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);\n	else\n		ksu_handle_execveat_sucompat(&fd, &filename, &argv, &envp, &flags);\n	#endif' fs/exec.c
        else
            sed -i '/if (IS_ERR(filename))/i\	#ifdef CONFIG_KSU\n	if (unlikely(ksu_execveat_hook))\n		ksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);\n	else\n		ksu_handle_execveat_sucompat(&fd, &filename, &argv, &envp, &flags);\n	#endif' fs/exec.c
        fi
        if grep -q "CONFIG_KSU" $i; then      
            echo "$i patch yes"
        else
            echo "$i patch fail"
        fi
        ;;

    ## open.c
    fs/open.c)
        if grep -q "long do_faccessat(int dfd, const char __user \*filename, int mode)" fs/open.c; then
            sed -i '/long do_faccessat(int dfd, const char __user \*filename, int mode)/i\#ifdef CONFIG_KSU\nextern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode,\n			 int *flags);\n#endif' fs/open.c
        else
            sed -i '/SYSCALL_DEFINE3(faccessat, int, dfd, const char __user \*, filename, int, mode)/i\#ifdef CONFIG_KSU\nextern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode,\n			 int *flags);\n#endif' fs/open.c
        fi
        sed -i '/if (mode & ~S_IRWXO)/i\	#ifdef CONFIG_KSU\n	ksu_handle_faccessat(&dfd, &filename, &mode, NULL);\n	#endif\n' fs/open.c
        if grep -q "CONFIG_KSU" $i; then      
            echo "$i patch yes"
        else
            echo "$i patch fail"
        fi
        ;;

    ## read_write.c
    fs/read_write.c)
        sed -i '/ssize_t vfs_read(struct file/i\#ifdef CONFIG_KSU\nextern bool ksu_vfs_read_hook __read_mostly;\nextern int ksu_handle_vfs_read(struct file **file_ptr, char __user **buf_ptr,\n		size_t *count_ptr, loff_t **pos);\n#endif' fs/read_write.c
        sed -i '/ssize_t vfs_read(struct file/,/ssize_t ret;/{/ssize_t ret;/a\
        #ifdef CONFIG_KSU\
        if (unlikely(ksu_vfs_read_hook))\
            ksu_handle_vfs_read(&file, &buf, &count, &pos);\
        #endif
        }' $i
        if grep -q "CONFIG_KSU" $i; then      
            echo "$i patch yes"
        else
            echo "$i patch fail"
        fi
        ;;

    ## stat.c
    fs/stat.c)
        if grep -q "int vfs_statx(int dfd, const char __user \*filename, int flags," fs/stat.c; then
            sed -i '/int vfs_statx(int dfd, const char __user \*filename, int flags,/i\#ifdef CONFIG_KSU\nextern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);\n#endif' fs/stat.c
            sed -i '/unsigned int lookup_flags = LOOKUP_FOLLOW | LOOKUP_AUTOMOUNT;/a\\n	#ifdef CONFIG_KSU\n	ksu_handle_stat(&dfd, &filename, &flags);\n	#endif' fs/stat.c
        else
            sed -i '/int vfs_fstatat(int dfd, const char __user \*filename, struct kstat \*stat,/i\#ifdef CONFIG_KSU\nextern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);\n#endif\n' fs/stat.c
            sed -i '/if ((flag & ~(AT_SYMLINK_NOFOLLOW | AT_NO_AUTOMOUNT |/i\	#ifdef CONFIG_KSU\n	ksu_handle_stat(&dfd, &filename, &flag);\n	#endif\n' fs/stat.c
        fi
        if grep -q "CONFIG_KSU" $i; then      
            echo "$i patch yes"
        else
            echo "$i patch fail"
        fi
        ;;

    # drivers/input changes
    ## input.c
    drivers/input/input.c)
        sed -i '/static void input_handle_event/i\#ifdef CONFIG_KSU\nextern bool ksu_input_hook __read_mostly;\nextern int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code, int *value);\n#endif\n' drivers/input/input.c
        sed -i '/int disposition = input_get_disposition(dev, type, code, &value);/a\	#ifdef CONFIG_KSU\n	if (unlikely(ksu_input_hook))\n		ksu_handle_input_handle_event(&type, &code, &value);\n	#endif' drivers/input/input.c
        if grep -q "CONFIG_KSU" $i; then      
            echo "$i patch yes"
        else
            echo "$i patch fail"
        fi
        ;;
        
    fs/devpts/inode.c)
        sed -i "/void \*devpts_get_priv(struct dentry \*dentry)/i\#ifdef CONFIG_KSU\nextern int ksu_handle_devpts(struct inode*);\n#endif" $i
        sed -i "/if (dentry->d_sb->s_magic != DEVPTS_SUPER_MAGIC)/i\#ifdef CONFIG_KSU\n	ksu_handle_devpts(dentry->d_inode);\n#endif" $i
        if grep -q "CONFIG_KSU" $i; then      
            echo "$i patch yes"
        else
            echo "$i patch fail"
        fi
        ;;    
        
    fs/namespace.c)
        if ! grep -q "int path_umount(struct path \*path, int flags)" $i; then      
            sed -i "s/int ksys_umount(char __user \*name, int flags)/$Tonamespace \nint ksys_umount(char __user *name, int flags)/g" $i
        fi
        if grep -q "int path_umount(struct path \*path, int flags)" $i; then      
            echo "$i patch yes"
        else
            echo "$i patch fail"
        fi
        ;;
    esac
    
done
